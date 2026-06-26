require_relative '../models/init'

class CategoryService
  class Error < StandardError; end
  class NotFoundError < Error; end
  class ProtectedError < Error; end
  class HasBooksError < Error; end
  class InvalidParentError < Error; end

  def self.create!(params)
    parent_id = params[:parent_id] || params['parent_id']
    name = params[:name] || params['name']
    code = params[:code] || params['code']
    position = params[:position] || params['position']

    if parent_id && parent_id.to_i > 0
      parent = Category[parent_id.to_i]
      raise InvalidParentError, '父级分类不存在' unless parent
    end

    cat = Category.new(
      name: name,
      code: code,
      parent_id: (parent_id && parent_id.to_i > 0) ? parent_id.to_i : nil,
      position: position,
      is_leaf: true
    )

    unless cat.valid?
      raise Error, "参数错误: #{cat.errors.full_messages.join(', ')}"
    end

    cat.save
    cat
  end

  def self.update!(id, params)
    cat = Category[id.to_i]
    raise NotFoundError, '分类不存在' unless cat
    raise ProtectedError, '系统分类「未分类」不允许修改' if cat.code == Category::UNCATEGORIZED_CODE

    if params.key?(:parent_id) || params.key?('parent_id')
      new_parent_id = params[:parent_id] || params['parent_id']
      if new_parent_id && new_parent_id.to_i > 0
        raise InvalidParentError, '父级分类不能是自身' if new_parent_id.to_i == cat.id
        if cat.descendants.map(&:id).include?(new_parent_id.to_i)
          raise InvalidParentError, '父级分类不能是自己的子分类'
        end
        raise InvalidParentError, '父级分类不存在' unless Category[new_parent_id.to_i]
      end
    end

    update_attrs = {}
    [:name, :code, :parent_id, :position, :is_leaf].each do |k|
      sk = k.to_s
      if params.key?(k) || params.key?(sk)
        val = params.key?(k) ? params[k] : params[sk]
        if k == :parent_id
          val = val.to_i if val && val.to_i > 0
          val = nil if val.nil? || val.to_s == '0' || val.to_s == ''
        end
        update_attrs[k] = val
      end
    end

    unless cat.update(update_attrs)
      raise Error, "参数错误: #{cat.errors.full_messages.join(', ')}"
    end

    cat
  end

  def self.delete_with_transfer!(id, transfer_to_id = nil)
    cat = Category[id.to_i]
    raise NotFoundError, '分类不存在' unless cat
    raise ProtectedError, '系统分类「未分类」不允许删除' if cat.code == Category::UNCATEGORIZED_CODE

    if transfer_to_id && transfer_to_id.to_i > 0
      target = Category[transfer_to_id.to_i]
      raise NotFoundError, '目标分类不存在' unless target
      target_id = target.id
    else
      target_id = Category.uncategorized_id
    end

    DB.transaction do
      all_ids = cat.descendants.map(&:id) << cat.id
      Book.where(category_id: all_ids).update(category_id: target_id)
      cat.destroy
    end

    { books_transferred_to: target_id }
  end

  def self.delete_strict!(id)
    cat = Category[id.to_i]
    raise NotFoundError, '分类不存在' unless cat
    raise ProtectedError, '系统分类「未分类」不允许删除' if cat.code == Category::UNCATEGORIZED_CODE

    all_ids = cat.descendants.map(&:id) << cat.id
    books_count = Book.where(category_id: all_ids).count
    if books_count > 0
      raise HasBooksError, "该分类及子分类下共有 #{books_count} 本图书，请先迁移图书后再删除"
    end

    DB.transaction do
      cat.destroy
    end

    {}
  end

  def self.get_detail(id, with_tree: false, with_path: false)
    cat = Category[id.to_i]
    raise NotFoundError, '分类不存在' unless cat

    data = with_tree ? cat.serializable_tree : cat.serializable_hash
    if with_path
      data[:path] = cat.ancestors.reverse.map { |a| { id: a.id, name: a.name } } +
                    [{ id: cat.id, name: cat.name }]
    end
    data
  end

  def self.list(params = {})
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    per_page = [per_page, 200].min
    offset = (page - 1) * per_page

    dataset = Category.dataset
    if params[:parent_id] && !params[:parent_id].to_s.empty?
      pid = (params[:parent_id].to_s == '0' || params[:parent_id].to_s == 'null') ? nil : params[:parent_id].to_i
      dataset = dataset.where(parent_id: pid)
    end
    if params[:level] && !params[:level].to_s.empty?
      dataset = dataset.where(level: params[:level].to_i)
    end
    if params[:name] && !params[:name].to_s.empty?
      dataset = dataset.where(Sequel.like(:name, "%#{params[:name]}%"))
    end

    total = dataset.count
    list = dataset.order(:level, :position).limit(per_page, offset).all

    {
      list: list.map(&:serializable_hash),
      total: total,
      page: page,
      per_page: per_page
    }
  end

  def self.tree(fix_orphans: false)
    Category.assign_uncategorized_to_orphan_books! if fix_orphans
    Category.tree
  end

  def self.books_for(id, params = {})
    cat = Category[id.to_i]
    raise NotFoundError, '分类不存在' unless cat

    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min
    offset = (page - 1) * per_page
    include_descendants = params[:include_descendants] == 'true' || params[:include_descendants] == true

    if include_descendants
      ids = cat.descendants.map(&:id) << cat.id
      dataset = Book.where(category_id: ids)
    else
      if cat.code == Category::UNCATEGORIZED_CODE
        dataset = Book.where(Sequel.|({ category_id: cat.id }, { category_id: nil }))
      else
        dataset = Book.where(category_id: cat.id)
      end
    end

    total = dataset.count
    books = dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all

    {
      category: cat.serializable_hash,
      include_descendants: include_descendants,
      list: books.map(&:serializable_hash),
      total: total,
      page: page,
      per_page: per_page
    }
  end

  def self.assign_book_category!(book_id, category_id)
    book = Book[book_id.to_i]
    raise NotFoundError, '图书不存在' unless book

    if category_id && category_id.to_i > 0
      cat = Category[category_id.to_i]
      raise NotFoundError, '分类不存在' unless cat
      target_id = category_id.to_i
    else
      target_id = Category.uncategorized_id
    end

    book.update(category_id: target_id)
    book
  end

  def self.batch_assign_books!(book_ids, category_id)
    book_ids = Array(book_ids).compact
    raise Error, '请选择图书' if book_ids.empty?

    if category_id && category_id.to_i > 0
      cat = Category[category_id.to_i]
      raise NotFoundError, '分类不存在' unless cat
      target_id = category_id.to_i
    else
      target_id = Category.uncategorized_id
    end

    count = Book.where(id: book_ids).update(category_id: target_id)
    { updated_count: count, category_id: target_id }
  end

  def self.available_parents(exclude_id = nil)
    list = Category.available_parents(exclude_id ? exclude_id.to_i : nil)
    list.map do |c|
      {
        id: c.id,
        parent_id: c.parent_id,
        name: c.name,
        level: c.level,
        is_leaf: c.is_leaf
      }
    end
  end

  def self.fix_orphan_books!
    Category.uncategorized_id
    count = Category.assign_uncategorized_to_orphan_books!
    { fixed_count: count }
  end
end
