module Audit
  class RecordRead
    # Writes one row of the read audit log: `reader` viewed the field group `group` of `record`. A person reading their own data is
    # not logged (nobody else saw it). It stores ids and the group name only, never a value, and raises when the row cannot be
    # written: the caller must not return data that was not logged.
    def self.call(reader:, record:, group:, request_id: nil)
      return Result.success if reader.to_s == record.id.to_s

      ReadAudit.create!(reader: reader.to_s, item_type: record.class.name, item_id: record.id, field_group: group.to_s, request_id:)
      Result.success
    end
  end
end
