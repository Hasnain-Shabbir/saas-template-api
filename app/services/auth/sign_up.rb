module Auth
  class SignUp
    def self.call(email:, password:)
      user = User.new(email:, password:)

      User.transaction do
        return invalid(user) unless user.save

        Result.success(user:, token: IssueToken.call(user))
      end
    rescue ActiveRecord::RecordNotUnique
      # Two sign ups with the same email at the same moment: the unique index decides.
      user.errors.add(:email, :taken)
      invalid(user)
    end

    def self.invalid(user)
      Errors.failure(Errors::VALIDATION_FAILED, errors: user.errors)
    end
    private_class_method :invalid
  end
end
