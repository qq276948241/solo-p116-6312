require_relative '../config/database'

class PointsLog < Sequel::Model
  many_to_one :member
  many_to_one :order

  EARN = 'earn'
  SPEND = 'spend'

  CHANGE_TYPES = [EARN, SPEND].freeze

  def serializable_hash
    {
      id: id,
      member_id: member_id,
      order_id: order_id,
      points_change: points_change,
      change_type: change_type,
      change_type_text: change_type_text,
      description: description,
      created_at: created_at
    }
  end

  def change_type_text
    {
      EARN => '获得',
      SPEND => '抵扣'
    }[change_type] || change_type
  end
end
