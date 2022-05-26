# frozen_string_literal: true

require "rake/clean"
CLEAN.add(
  "ext/selma/libhlolhtml",
  "lib/selma/[0-9].[0-9]",
  "lib/selma/selma.{bundle,jar,rb,so}",
  "pkg",
  "tmp"
)
CLOBBER.add("ports/*").exclude(%r{ports/archives$})
