module Profiles
  class Update
    # Saves the profile of the logged-in user: all four fields are required. Sending the same data again changes nothing
    # (no write, `updated_at` stays), and new data replaces the old. The user passed in is the caller's own: no id is taken.
    # Saving a complete profile also finishes the profile onboarding step, in the same transaction (see `Onboarding::Sync`).
    def self.call(user:, first_name:, last_name:, date_of_birth:, phone:)
      # The row lock makes two requests of one user take turns. It does not reload the user (`with_lock` would drop the new attributes).
      user.transaction do
        User.where(id: user.id).lock.pick(:id)
        user.assign_attributes(first_name:, last_name:, date_of_birth:, phone:)
        user.validate
        # An empty field is "is required" (a blank name or phone is normalized to nothing). Only a filled one can be "invalid".
        User::PROFILE_FIELDS.each { |field| user.errors.add(field, Errors::FIELD_REQUIRED.message) if user[field].blank? }
        next Errors.failure(Errors::VALIDATION_FAILED, errors: user.errors) if user.errors.any?

        user.save!
        Onboarding::Sync.call(user:)
        Result.success(user)
      end
    end
  end
end
