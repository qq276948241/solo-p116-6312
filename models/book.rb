require_relative '../config/database'

class Book < Sequel::Model
  plugin :validation_helpers

  AVAILABLE = 'available'
  SOLD = 'sold'
  RESERVED = 'reserved'

  STATUSES = [AVAILABLE, SOLD, RESERVED].freeze

  CONDITIONS = ['全新', '九成新', '八成新', '七成新', '六成新及以下'].freeze

  def validate
    super
    validates_presence [:title, :condition, :purchase_price, :sale_price]
    validates_includes STATUSES, :status
    validates_includes CONDITIONS, :condition
    validates_numeric [:purchase_price, :sale_price]
  end

  def available?
    status == AVAILABLE
  end

  def sold?
    status == SOLD
  end

  def reserved?
    status == RESERVED
  end

  def mark_as_reserved!
    update(status: RESERVED)
  end

  def mark_as_sold!
    update(status: SOLD)
  end

  def mark_as_available!
    update(status: AVAILABLE)
  end

  def serializable_hash
    {
      id: id,
      isbn: isbn,
      title: title,
      author: author,
      publisher: publisher,
      publish_date: publish_date,
      condition: condition,
      purchase_price: purchase_price.to_f,
      sale_price: sale_price.to_f,
      status: status,
      status_text: status_text,
      notes: notes,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def status_text
    {
      AVAILABLE => '在架',
      SOLD => '已售',
      RESERVED => '预订中'
    }[status] || status
  end

  def self.search(params = {})
    dataset = self
    if params[:isbn] && !params[:isbn].empty?
      dataset = dataset.where(Sequel.like(:isbn, "%#{params[:isbn]}%"))
    end
    if params[:title] && !params[:title].empty?
      dataset = dataset.where(Sequel.like(:title, "%#{params[:title]}%"))
    end
    if params[:status] && !params[:status].empty?
      dataset = dataset.where(status: params[:status])
    end
    dataset
  end
end
