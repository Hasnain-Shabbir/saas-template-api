# Turns a failed service Result into the `errors` list of a payload.
module ResultErrors
  private

  def errors_from(result)
    return [] if result.success?
    return [ { message: result.message, path: [ "input" ], code: result.code } ] unless result.errors

    result.errors.map do |error|
      { message: error.full_message, path: [ "input", error.attribute.to_s.camelize(:lower) ], code: result.code }
    end
  end
end
