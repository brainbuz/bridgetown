# frozen_string_literal: true

module Bridgetown
  module LayoutPlaceable
    # Determine whether the file should be placed into layouts.
    #
    # @return [Boolean] false if the document is an asset file or if the front matter
    #   specifies `layout: none`
    def place_in_layout?
      no_layout?.!
    end

    def no_layout?
      data.layout.nil? || data.layout == "none" || data.layout == false
    end
  end
end
