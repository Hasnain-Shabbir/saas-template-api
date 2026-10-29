module Addresses
  class Update
    # Saves the US address of the logged-in user. Everything but line 2 is required. Sending the same data again changes nothing
    # (no write, `updated_at` stays), and new data replaces the old (so an empty line 2 clears it). The user passed in is the caller's
    # own: no id is taken. Saving a complete address also finishes the address onboarding step, in the same transaction (see `Onboarding::Sync`).
    def self.call(user:, address_line_1:, city:, state:, postal_code:, country:, address_line_2: nil)
      # The row lock makes two requests of one user take turns. It does not reload the user (`with_lock` would drop the new attributes).
      user.transaction do
        User.where(id: user.id).lock.pick(:id)
        user.assign_attributes(address_line_1:, address_line_2:, city:, state:, postal_code:, country:)
        user.validate
        # An empty field is "is required" (a blank value is normalized to nothing). Only a filled one can be "invalid".
        User::ADDRESS_REQUIRED_FIELDS.each { |field| user.errors.add(field, Errors::FIELD_REQUIRED.message) if user[field].blank? }
        next Errors.failure(Errors::VALIDATION_FAILED, errors: user.errors) if user.errors.any?

        user.save!
        Onboarding::Sync.call(user:)
        Result.success(user)
      end
    end
  end
end
