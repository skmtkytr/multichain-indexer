# frozen_string_literal: true

# Load all transfer decoder plugins on boot.
# Each decoder auto-registers itself via TransferDecoder.register_log_decoder / register_extra_decoder.
Rails.application.config.after_initialize do
  Dir[Rails.root.join('app/services/decoders/*.rb')].each { |f| require f }

  decoder_count = TransferDecoder.log_decoders.size + TransferDecoder.extra_decoders.size
  Rails.logger.info("TransferDecoder: #{decoder_count} decoders registered " \
                     "(#{TransferDecoder.log_decoders.size} log, #{TransferDecoder.extra_decoders.size} extra)")
end
