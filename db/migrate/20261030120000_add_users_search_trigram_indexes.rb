# Trigram indexes for the admin users search (Layer 3, step 1): partial, case-insensitive match on email, first name and last name.
# They are expression indexes on `lower(...)`, and `Users::SearchQuery` (`User.matching`) uses the same expression, so the planner can use them.
# `email` is citext, so it is cast to text: pg_trgm has no operator class for citext.
class AddUsersSearchTrigramIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :users, "lower(email::text) gin_trgm_ops", using: :gin, name: "index_users_on_email_trgm", algorithm: :concurrently
    add_index :users, "lower(first_name) gin_trgm_ops", using: :gin, name: "index_users_on_first_name_trgm", algorithm: :concurrently
    add_index :users, "lower(last_name) gin_trgm_ops", using: :gin, name: "index_users_on_last_name_trgm", algorithm: :concurrently
  end
end
