# Creates the first super_admin from configuration. No credential lives in the repo:
# set SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD in the environment, then run bin/rails db:seed.
# Safe to run again: an existing user is never changed (no role change, no new password).
email = ENV["SUPER_ADMIN_EMAIL"].presence
password = ENV["SUPER_ADMIN_PASSWORD"].presence

if email && password
  User.find_or_create_by!(email:) do |user|
    user.password = password
    user.role = :super_admin
  end
else
  puts "Skipped the super admin: set SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD."
end
