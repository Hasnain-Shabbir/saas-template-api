# Trigram indexes make a "contains" search (ILIKE '%part%') fast. First user: the email log search by address.
class EnablePgTrgm < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
  end
end
