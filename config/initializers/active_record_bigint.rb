# frozen_string_literal: true

# Allow decimal columns to accept values larger than 64-bit integers.
# EVM chains routinely produce values exceeding bigint range
# (e.g. ETH value in wei: 80 ETH = 8×10^19 > 9.2×10^18 bigint max).
# Rails 8.1 raises IntegerOutOf64BitRange by default even for decimal columns.
ActiveRecord.raise_int_wider_than_64bit = false
