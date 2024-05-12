require 'singleton'
require 'forwardable'

# This is the root configatron object, and contains methods which
# operate on the entire configatron hierarchy.
class Configatron::RootStore < BasicObject
  include ::Singleton
  extend ::Forwardable

  attr_reader :store

  # Have one global RootStore instance, but allow people to create
  # their own parallel ones if they desire.
  class << self
    public :new
  end

  @@cow = 0

  def initialize
    @locked = false
    @cow = nil

    @temporary_locks = []
    @temporary_states = []

    reset!
  end

  def __cow
    @cow
  end

  def __cow_path(path)
    start = @store.__cow_clone

    node = start
    branch = path.map do |key|
      node = node[key]
      node.__cow_clone
    end
    nodes = [start] + branch

    # [node1, node2, node3] with
    # [node2, node3, node4] and
    # ['key1', 'key2, 'key3']
    nodes[0...-1].zip(nodes[1..-1], path) do |parent, child, key|
      # These are all cow_clones, so won't trigger a further cow
      # modification.
      parent[key] = child
    end

    @store = nodes.first
    nodes.last
  end

  def method_missing(name, *args, &block)
    store.__send__(name, *args, &block)
  end

  def reset!
    @store = ::Configatron::Store.new(self)
  end

  def temp(marshal: false, &block)
    # Marshal.load( Marshal.dump(a) )
    temp_start(marshal: marshal)
    begin
      yield
    ensure
      temp_end(marshal: marshal)
    end
  end

  def temp_start(marshal: false)
    @temp_cow = @cow

    # Just need to have a unique Copy-on-Write generation ID
    @cow = @@cow += 1

    @temporary_locks.push(@locked)

    possibly_marshaled_store = if marshal
      ::Marshal.dump(@store)
    else
      @store
    end
    @temporary_states.push(possibly_marshaled_store)
  end

  def temp_end(marshal: false)
    @cow = @temp_cow

    @locked = @temporary_locks.pop

    possibly_marshaled_store = if marshal
      ::Marshal.load(@temporary_states.pop)
    else
      @temporary_states.pop
    end

    @store = possibly_marshaled_store
  end

  def locked?
    @locked
  end

  def lock!(&blk)
    if blk
      orig = @locked
      begin
        @locked = true
        blk.call
      ensure
        @locked = orig
      end
    else
      @locked = true
    end
  end

  def unlock!(&blk)
    if blk
      orig = @locked
      begin
        @locked = false
        blk.call
      ensure
        @locked = orig
      end
    else
      @locked = false
    end
  end

  def_delegator :@store, :to_s
  def_delegator :@store, :inspect
end
