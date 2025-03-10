# frozen_string_literal: true

module Bridgetown
  module Drops
    class Drop < Liquid::Drop
      include Enumerable

      NON_CONTENT_METHODS = [:fallback_data, :collapse_document].freeze

      # Get or set whether the drop class is mutable.
      # Mutability determines whether or not pre-defined fields may be
      # overwritten.
      #
      # @param is_mutable [Boolean] set mutability of the class
      #
      # @return [Boolean] the mutability of the class
      def self.mutable(is_mutable = nil)
        @is_mutable = is_mutable || false
      end

      # @return [Boolean] the mutability of the class
      def self.mutable?
        @is_mutable
      end

      # Create a new Drop
      #
      # @param obj [Object] the Bridgetown Site, Collection, or Resource required by the
      # drop.
      def initialize(obj) # rubocop:disable Lint/MissingSuper
        @obj = obj
      end

      # Access a method in the Drop or a field in the underlying hash data.
      # If mutable, checks the mutations first. Then checks the methods,
      # and finally check the underlying hash (e.g. document front matter)
      # if all the previous places didn't match.
      #
      # @param key [String] key whose value to fetch
      # @return [Object, nil] returns the value for the given key if present
      def [](key)
        if self.class.mutable? && mutations.key?(key)
          mutations[key]
        elsif self.class.invokable? key
          public_send key
        else
          fallback_data[key]
        end
      end
      alias_method :invoke_drop, :[]

      # Set a field in the Drop. If mutable, sets in the mutations and returns. If not mutable,
      # checks first if it's trying to override a Drop method and raises an exception if so.
      # If not mutable and the key is not a method on the Drop, then it sets the key to the value
      # in the underlying hash (e.g. document front matter)
      #
      # @param key [String] key whose value to set
      # @param val [Object] what to set the key's value to
      # @return [Object] the value the key was set to unless the Drop is not mutable
      #   and the key matches a method in which case it raises an exception
      def []=(key, val)
        setter = "#{key}="
        if respond_to?(setter)
          public_send(setter, val)
        elsif respond_to?(key.to_s)
          unless self.class.mutable?
            raise Errors::FatalException, "Key #{key} cannot be set in the drop."
          end

          mutations[key] = val
        else
          fallback_data[key] = val
        end
      end

      # Generates a list of strings which correspond to content getter
      # methods.
      #
      # @return [Array<String>] method-specific keys
      def content_methods
        @content_methods ||= (
          self.class.instance_methods \
            - Bridgetown::Drops::Drop.instance_methods \
            - NON_CONTENT_METHODS
        ).map(&:to_s).reject do |method|
          method.end_with?("=")
        end
      end

      # Check if key exists in Drop
      #
      # @param key [String] key whose value to set
      # @return [Boolean] true if the given key is present
      def key?(key)
        return false if key.nil?
        return true if self.class.mutable? && mutations.key?(key)

        respond_to?(key) || fallback_data.key?(key)
      end

      # Generates a list of keys with user content as their values.
      # This gathers up the Drop methods and keys of the mutations and
      # underlying data hashes and performs a set union to ensure a list
      # of unique keys for the Drop.
      #
      # @return [Array<String>]
      def keys
        (content_methods |
          mutations.keys |
          fallback_data.keys).flatten
      end

      # Generate a Hash representation of the Drop by resolving each key's
      # value. It includes Drop methods, mutations, and the underlying object's
      # data. See the documentation for Drop#keys for more.
      #
      # @return [Hash<String, Object>] all the keys and values resolved
      def to_h
        keys.each_with_object({}) do |(key, _), result|
          result[key] = self[key]
        end
      end
      alias_method :to_hash, :to_h

      # Inspect the drop's keys and values through a JSON representation
      # of its keys and values.
      #
      # @return [String]
      def inspect
        JSON.pretty_generate to_h
      end

      # Generate a Hash for use in generating JSON. Essentially an alias for `to_h`
      #
      # @return [Hash<String, Object>] all the keys and values resolved
      def hash_for_json(*)
        to_h
      end

      # Generate a JSON representation of the Drop
      #
      # @param state [JSON::State] object which determines the state of current processing
      # @return [String] JSON representation of the Drop
      def to_json(state = nil)
        JSON.generate(hash_for_json(state), state)
      end

      # Collects all the keys and passes each to the block in turn
      def each_key(&)
        keys.each(&)
      end

      def each
        each_key.each do |key|
          yield key, self[key]
        end
      end

      def merge(other, &block)
        dup.tap do |me|
          if block.nil?
            me.merge!(other)
          else
            me.merge!(other, block)
          end
        end
      end

      def merge!(other)
        other.each_key do |key|
          if block_given?
            self[key] = yield key, self[key], other[key]
          else
            if Utils.mergeable?(self[key]) && Utils.mergeable?(other[key])
              self[key] = Utils.deep_merge_hashes(self[key], other[key])
              next
            end

            self[key] = other[key] unless other[key].nil?
          end
        end
      end

      # Imitate `Hash.fetch` method in Drop
      #
      # @return [Object] value if key is present in Drop, otherwise returns default value.
      #   KeyError is raised if key is not present and no default value given
      def fetch(key, default = nil, &block)
        return self[key] if key?(key)
        raise KeyError, %(key not found: "#{key}") if default.nil? && block.nil?
        return yield(key) unless block.nil?

        default unless default.nil?
      end

      private

      def mutations
        @mutations ||= {}
      end
    end
  end
end
