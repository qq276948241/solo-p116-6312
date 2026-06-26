require_relative '../config/database'

class Book < Sequel::Model
  plugin :validation_helpers

  many_to_one :category, allow_nil: true

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

  def before_create
    super
    self.category_id ||= Category.uncategorized_id
  end

  def before_save
    super
    if category_id.nil?
      self.category_id = Category.uncategorized_id
    end
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
    c = category
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
      category_id: category_id,
      category_name: c ? c.name : Category::UNCATEGORIZED_NAME,
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
    if params[:category_id] && !params[:category_id].empty?
      cid = params[:category_id].to_i
      child_ids = Category[cid]&.descendants.map(&:id) || []
      child_ids << cid
      uncategorized_id = nil
      if cid == Category.uncategorized_id
        uncategorized_id = Category.uncategorized_id
        dataset = dataset.where(Sequel.|({ category_id: child_ids }, { category_id => nil }))
      else
        dataset = dataset.where(category_id: child_ids)
      end
    end
    dataset
  end
end
