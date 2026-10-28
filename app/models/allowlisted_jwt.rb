class AllowlistedJwt < ApplicationRecord
  belongs_to :user

  validates :jti, :exp, presence: true
end
