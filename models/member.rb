require_relative '../config/database'
require_relative 'points_log'

class Member < Sequel::Model
  plugin :validation_helpers
  one_to_many :points_logs
  one_to_many :orders

  def validate
    super
    validates_presence [:phone]
    validates_unique :phone
    validates_format /\A1[3-9]\d{9}\z/, :phone if phone && !phone.empty?
  end

  def add_points!(points, order_id: nil, description: nil)
    DB.transaction do
      update(points: self.points + points)
      PointsLog.create(
        member_id: id,
        order_id: order_id,
        points_change: points,
        change_type: points > 0 ? 'earn' : 'spend',
        description: description || (points > 0 ? '消费赚取积分' : '使用积分抵扣')
      )
    end
  end

  def spend_points!(points, order_id: nil)
    raise '积分不足' if points > self.points
    add_points!(-points, order_id: order_id)
  end

  def points_logs_with_order(page = 1, per_page = 20)
    offset = (page - 1) * per_page
    points_logs_dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all
  end

  def serializable_hash(with_logs: false)
    data = {
      id: id,
      phone: phone,
      name: name,
      points: points || 0,
      created_at: created_at,
      updated_at: updated_at
    }
    if with_logs
      data[:points_logs] = points_logs.map(&:serializable_hash)
    end
    data
  end
end
