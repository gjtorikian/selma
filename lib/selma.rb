# frozen_string_literal: true

require "rbconfig"

require_relative "selma/extension"

begin
require "amazing_print"
require "debug"
rescue LoadError; end # rubocop:disable Lint/SuppressedException
