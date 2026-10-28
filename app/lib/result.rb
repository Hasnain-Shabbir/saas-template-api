# What a service returns: a value on success, or a stable code and a safe message on failure.
# `errors` carries the model's validation errors when a record was invalid.
class Result
  attr_reader :value, :code, :message, :errors

  def self.success(value = nil)
    new(value:)
  end

  def self.failure(code:, message:, errors: nil)
    new(code:, message:, errors:)
  end

  def initialize(value: nil, code: nil, message: nil, errors: nil)
    @value = value
    @code = code
    @message = message
    @errors = errors
  end

  def success?
    code.nil?
  end

  def failure?
    !success?
  end
end
