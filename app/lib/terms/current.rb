module Terms
  # The version of the terms and privacy policy a user must accept. The client reads it from the page it shows and sends it back, so
  # the server knows which text was accepted. Change it when the text changes (a new version does not re-open a finished step).
  module Current
    VERSION = "2026-10-01".freeze
  end
end
