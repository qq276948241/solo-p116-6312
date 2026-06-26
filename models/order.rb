require_relative '../config/database'
require_relative 'order_log'
require_relative 'book'
require_relative 'member'

class Order < Sequel::Model
  plugin :validation_helpers
  many_to_one :member
  one_to_many :order_items
  one_to_many :order_logs

  PENDING = 'pending'
  CONFIRMED = 'confirmed'
  PICKED_UP = 'picked_up'
  CANCELLED = 'cancelled'
  EXPIRED = 'expired'

  STATUSES = [PENDING, CONFIRMED, PICKED_UP, CANCELLED, EXPIRED].freeze

  STATUS_TEXT = {
    PENDING => '待取货',
    CONFIRMED => '已确认',
    PICKED_UP => '已取货',
    CANCELLED => '已取消',
    EXPIRED => '已作废'
  }.freeze

  EXPIRE_DAYS = 3

  def validate
    super
    validates_presence [:order_no, :total_amount, :status, :expire_at]
    validates_unique :order_no
    validates_includes STATUSES, :status
  end

  def status_text
    STATUS_TEXT[status] || status
  end

  def pending?
    status == PENDING
  end

  def confirmed?
    status == CONFIRMED
  end

  def picked_up?
    status == PICKED_UP
  end

  def cancelled?
    status == CANCELLED
  end

  def expired?
    status == EXPIRED
  end

  def books
    Book.where(id: order_items.map(&:book_id)).all
  end

  def confirm!(operator: 'system', remark: nil)
    return if confirmed? || picked_up?
    DB.transaction do
      old_status = status
      update(status: CONFIRMED)
      add_order_log(old_status, CONFIRMED, operator, remark)
    end
  end

  def pickup!(operator: 'system', remark: nil)
    return if picked_up?
    DB.transaction do
      old_status = status
      update(status: PICKED_UP)
      add_order_log(old_status, PICKED_UP, operator, remark)

      if member && points_earned.to_i > 0
        member.add_points!(points_earned, order_id: id, description: "订单#{order_no}消费赚取积分")
      end

      order_items.each do |item|
        book = Book[item.book_id]
        book.mark_as_sold! if book && !book.sold?
      end
    end
  end

  def cancel!(operator: 'system', remark: nil)
    return if picked_up? || cancelled? || expired?
    DB.transaction do
      old_status = status

      if member && points_used.to_i > 0
        member.add_points!(points_used, order_id: id, description: "订单#{order_no}取消返还积分")
      end

      order_items.each do |item|
        book = Book[item.book_id]
        book.mark_as_available! if book && book.reserved?
      end

      update(status: CANCELLED)
      add_order_log(old_status, CANCELLED, operator, remark)
    end
  end

  def expire!(operator: 'system')
    return unless pending?
    return unless Time.now > expire_at

    DB.transaction do
      old_status = status

      if member && points_used.to_i > 0
        member.add_points!(points_used, order_id: id, description: "订单#{order_no}超时作废返还积分")
      end

      order_items.each do |item|
        book = Book[item.book_id]
        book.mark_as_available! if book && book.reserved?
      end

      update(status: EXPIRED)
      add_order_log(old_status, EXPIRED, operator, '超3天未取货自动作废')
    end
  end

  def self.expire_overdue!
    where(status: PENDING).where { expire_at < Time.now }.each do |order|
      order.expire!
    end
  end

  def self.generate_order_no
    "BS#{Time.now.strftime('%Y%m%d%H%M%S')}#{rand(1000..9999)}"
  end

  def self.create_with_items!(member: nil, book_ids: [], points_to_use: 0, operator: 'system')
    DB.transaction do
      books = Book.where(id: book_ids, status: Book::AVAILABLE).all
      raise '存在不可用的图书' if books.size != book_ids.uniq.size

      total_amount = books.sum { |b| b.sale_price }
      points_used = [points_to_use.to_i, member&.points.to_i, total_amount.to_i].min
      actual_pay = total_amount - points_used
      points_earned = actual_pay.to_i

      if member && points_used > 0
        member.spend_points!(points_used)
      end

      order = create(
        order_no: generate_order_no,
        member_id: member&.id,
        total_amount: total_amount,
        points_used: points_used,
        points_earned: points_earned,
        status: PENDING,
        expire_at: Time.now + EXPIRE_DAYS * 24 * 3600
      )

      books.each do |book|
        OrderItem.create(
          order_id: order.id,
          book_id: book.id,
          price: book.sale_price
        )
        book.mark_as_reserved!
      end

      order.add_order_log(nil, PENDING, operator, '创建订单')
      order
    end
  end

  def add_order_log(from, to, operator, remark)
    OrderLog.create(
      order_id: id,
      from_status: from,
      to_status: to,
      operator: operator,
      remark: remark
    )
  end

  def serializable_hash(with_items: false, with_logs: false, with_member: false)
    data = {
      id: id,
      order_no: order_no,
      total_amount: total_amount.to_f,
      points_used: points_used,
      points_earned: points_earned,
      status: status,
      status_text: status_text,
      expire_at: expire_at,
      created_at: created_at,
      updated_at: updated_at
    }
    data[:member] = member.serializable_hash if with_member && member
    if with_items
      data[:order_items] = order_items.map do |item|
        book = Book[item.book_id]
        {
          id: item.id,
          book_id: item.book_id,
          price: item.price.to_f,
          book: book&.serializable_hash
        }
      end
    end
    data[:order_logs] = order_logs.map(&:serializable_hash) if with_logs
    data
  end
end
