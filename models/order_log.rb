require_relative '../config/database'

class OrderLog < Sequel::Model
  many_to_one :order

  def serializable_hash
    {
      id: id,
      order_id: order_id,
      from_status: from_status,
      to_status: to_status,
      from_status_text: status_text(from_status),
      to_status_text: status_text(to_status),
      operator: operator,
      remark: remark,
      created_at: created_at
    }
  end

  private

  def status_text(status)
    Order::STATUS_TEXT[status] || status
  end
end
