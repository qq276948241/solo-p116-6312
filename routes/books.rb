require_relative '../models/init'

class Bookstore < Sinatra::Base
  before '/api/books*' do
    content_type :json, charset: 'utf-8'
  end

  before '/api/categories*' do
    content_type :json, charset: 'utf-8'
  end

  get '/api/books' do
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min

    search_params = params.slice(:isbn, :title, :status, :category_id)
    dataset = Book.search(search_params)
    total = dataset.count
    offset = (page - 1) * per_page

    books = dataset.eager(:category).order(Sequel.desc(:created_at)).limit(per_page, offset).all

    {
      code: 0,
      message: 'success',
      data: {
        list: books.map(&:serializable_hash),
        total: total,
        page: page,
        per_page: per_page
      }
    }.to_json
  end

  get '/api/books/:id' do
    book = Book.eager(:category).where(id: params[:id].to_i).first

    unless book
      status 404
      return { code: 404, message: '图书不存在', data: nil }.to_json
    end

    {
      code: 0,
      message: 'success',
      data: book.serializable_hash
    }.to_json
  end

  post '/api/books' do
    body = JSON.parse(request.body.read) rescue {}

    book = Book.new(
      isbn: body['isbn'],
      title: body['title'],
      author: body['author'],
      publisher: body['publisher'],
      publish_date: body['publish_date'],
      condition: body['condition'],
      purchase_price: body['purchase_price'],
      sale_price: body['sale_price'],
      status: body['status'] || Book::AVAILABLE,
      category_id: body['category_id'],
      notes: body['notes']
    )

    unless book.valid?
      status 422
      return {
        code: 422,
        message: '参数错误',
        data: book.errors.full_messages
      }.to_json
    end

    book.save

    {
      code: 0,
      message: '图书上架成功',
      data: book.serializable_hash
    }.to_json
  end

  put '/api/books/:id' do
    book = Book[params[:id].to_i]

    unless book
      status 404
      return { code: 404, message: '图书不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}

    update_attrs = {}
    [:isbn, :title, :author, :publisher, :publish_date,
     :condition, :purchase_price, :sale_price, :status, :category_id, :notes].each do |k|
      update_attrs[k] = body[k.to_s] if body.key?(k.to_s)
    end

    unless book.update(update_attrs)
      status 422
      return {
        code: 422,
        message: '参数错误',
        data: book.errors.full_messages
      }.to_json
    end

    {
      code: 0,
      message: '更新成功',
      data: book.serializable_hash
    }.to_json
  end

  patch '/api/books/:id/status' do
    book = Book[params[:id].to_i]

    unless book
      status 404
      return { code: 404, message: '图书不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}
    new_status = body['status']

    unless Book::STATUSES.include?(new_status)
      status 422
      return {
        code: 422,
        message: "状态必须是: #{Book::STATUSES.join(', ')}",
        data: nil
      }.to_json
    end

    book.update(status: new_status)

    {
      code: 0,
      message: '状态更新成功',
      data: book.serializable_hash
    }.to_json
  end

  patch '/api/books/:id/category' do
    book = Book[params[:id].to_i]

    unless book
      status 404
      return { code: 404, message: '图书不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}
    category_id = body['category_id']

    if category_id
      cat = Category[category_id.to_i]
      unless cat
        status 422
        return { code: 422, message: '分类不存在', data: nil }.to_json
      end
    else
      category_id = Category.uncategorized_id
    end

    book.update(category_id: category_id)

    {
      code: 0,
      message: '分类设置成功',
      data: book.serializable_hash
    }.to_json
  end

  post '/api/books/categories/batch_assign' do
    body = JSON.parse(request.body.read) rescue {}
    book_ids = body['book_ids'] || []
    category_id = body['category_id']

    if book_ids.empty?
      status 422
      return { code: 422, message: '请选择图书', data: nil }.to_json
    end

    if category_id && category_id.to_i > 0
      cat = Category[category_id.to_i]
      unless cat
        status 422
        return { code: 422, message: '分类不存在', data: nil }.to_json
      end
      target_id = category_id.to_i
    else
      target_id = Category.uncategorized_id
    end

    count = Book.where(id: book_ids).update(category_id: target_id)

    {
      code: 0,
      message: "已批量更新 #{count} 本图书的分类",
      data: { updated_count: count, category_id: target_id }
    }.to_json
  end

  delete '/api/books/:id' do
    book = Book[params[:id].to_i]

    unless book
      status 404
      return { code: 404, message: '图书不存在', data: nil }.to_json
    end

    if OrderItem.where(book_id: book.id).count > 0
      status 422
      return {
        code: 422,
        message: '该图书已有订单记录，无法删除',
        data: nil
      }.to_json
    end

    book.destroy

    {
      code: 0,
      message: '删除成功',
      data: nil
    }.to_json
  end

  get '/api/books/meta/conditions' do
    {
      code: 0,
      message: 'success',
      data: Book::CONDITIONS
    }.to_json
  end

  get '/api/books/meta/statuses' do
    {
      code: 0,
      message: 'success',
      data: Book::STATUSES.map { |s| { key: s, text: Book.new(status: s).status_text } }
    }.to_json
  end

  # ============ Categories ============

  get '/api/categories' do
    format = params[:format] || 'list'

    if format == 'tree'
      {
        code: 0,
        message: 'success',
        data: Category.tree
      }.to_json
    else
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 50).to_i
      per_page = [per_page, 200].min
      offset = (page - 1) * per_page

      dataset = Category.dataset
      if params[:parent_id] && !params[:parent_id].empty?
        pid = params[:parent_id] == '0' || params[:parent_id] == 'null' ? nil : params[:parent_id].to_i
        dataset = dataset.where(parent_id: pid)
      end
      if params[:level] && !params[:level].empty?
        dataset = dataset.where(level: params[:level].to_i)
      end
      if params[:name] && !params[:name].empty?
        dataset = dataset.where(Sequel.like(:name, "%#{params[:name]}%"))
      end

      total = dataset.count
      list = dataset.order(:level, :position).limit(per_page, offset).all

      {
        code: 0,
        message: 'success',
        data: {
          list: list.map(&:serializable_hash),
          total: total,
          page: page,
          per_page: per_page
        }
      }.to_json
    end
  end

  get '/api/categories/tree' do
    Category.assign_uncategorized_to_orphan_books!

    {
      code: 0,
      message: 'success',
      data: Category.tree
    }.to_json
  end

  get '/api/categories/:id' do
    cat = Category[params[:id].to_i]

    unless cat
      status 404
      return { code: 404, message: '分类不存在', data: nil }.to_json
    end

    with_tree = params[:with_tree] == 'true'
    data = with_tree ? cat.serializable_tree : cat.serializable_hash

    if params[:with_path] == 'true'
      data[:path] = cat.ancestors.reverse.map { |a| { id: a.id, name: a.name } } +
                    [{ id: cat.id, name: cat.name }]
    end

    {
      code: 0,
      message: 'success',
      data: data
    }.to_json
  end

  get '/api/categories/:id/books' do
    cat = Category[params[:id].to_i]

    unless cat
      status 404
      return { code: 404, message: '分类不存在', data: nil }.to_json
    end

    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min
    offset = (page - 1) * per_page
    include_descendants = params[:include_descendants] == 'true'

    if include_descendants
      ids = cat.descendants.map(&:id) << cat.id
      dataset = Book.where(category_id: ids)
    else
      if cat.code == Category::UNCATEGORIZED_CODE
        dataset = Book.where(Sequel.|({ category_id: cat.id }, { category_id => nil }))
      else
        dataset = Book.where(category_id: cat.id)
      end
    end

    total = dataset.count
    books = dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all

    {
      code: 0,
      message: 'success',
      data: {
        category: cat.serializable_hash,
        include_descendants: include_descendants,
        list: books.map(&:serializable_hash),
        total: total,
        page: page,
        per_page: per_page
      }
    }.to_json
  end

  post '/api/categories' do
    body = JSON.parse(request.body.read) rescue {}

    parent_id = body['parent_id']
    if parent_id && parent_id.to_i > 0
      parent = Category[parent_id.to_i]
      unless parent
        status 422
        return { code: 422, message: '父级分类不存在', data: nil }.to_json
      end
    end

    cat = Category.new(
      name: body['name'],
      code: body['code'],
      parent_id: (parent_id && parent_id.to_i > 0) ? parent_id.to_i : nil,
      position: body['position'],
      is_leaf: true
    )

    unless cat.valid?
      status 422
      return {
        code: 422,
        message: '参数错误',
        data: cat.errors.full_messages
      }.to_json
    end

    cat.save

    {
      code: 0,
      message: '分类创建成功',
      data: cat.serializable_hash
    }.to_json
  end

  put '/api/categories/:id' do
    cat = Category[params[:id].to_i]

    unless cat
      status 404
      return { code: 404, message: '分类不存在', data: nil }.to_json
    end

    if cat.code == Category::UNCATEGORIZED_CODE
      status 422
      return { code: 422, message: '系统分类「未分类」不允许修改', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}

    if body.key?('parent_id')
      new_parent_id = body['parent_id']
      if new_parent_id && new_parent_id.to_i > 0
        if new_parent_id.to_i == cat.id
          status 422
          return { code: 422, message: '父级分类不能是自身', data: nil }.to_json
        end
        if cat.descendants.map(&:id).include?(new_parent_id.to_i)
          status 422
          return { code: 422, message: '父级分类不能是自己的子分类', data: nil }.to_json
        end
        unless Category[new_parent_id.to_i]
          status 422
          return { code: 422, message: '父级分类不存在', data: nil }.to_json
        end
      end
    end

    update_attrs = {}
    [:name, :code, :parent_id, :position, :is_leaf].each do |k|
      if body.key?(k.to_s)
        val = body[k.to_s]
        val = val.to_i if k == :parent_id && val && val.to_i > 0
        val = nil if k == :parent_id && (val.nil? || val.to_s == '0' || val.to_s == '')
        update_attrs[k] = val
      end
    end

    unless cat.update(update_attrs)
      status 422
      return {
        code: 422,
        message: '参数错误',
        data: cat.errors.full_messages
      }.to_json
    end

    {
      code: 0,
      message: '分类更新成功',
      data: cat.serializable_hash
    }.to_json
  end

  delete '/api/categories/:id' do
    cat = Category[params[:id].to_i]

    unless cat
      status 404
      return { code: 404, message: '分类不存在', data: nil }.to_json
    end

    if cat.code == Category::UNCATEGORIZED_CODE
      status 422
      return { code: 422, message: '系统分类「未分类」不允许删除', data: nil }.to_json
    end

    transfer_books_to = params['transfer_books_to']
    if transfer_books_to && transfer_books_to.to_i > 0
      target = Category[transfer_books_to.to_i]
      unless target
        status 422
        return { code: 422, message: '目标分类不存在', data: nil }.to_json
      end
      target_id = target.id
    else
      target_id = Category.uncategorized_id
    end

    DB.transaction do
      all_ids = cat.descendants.map(&:id) << cat.id
      Book.where(category_id: all_ids).update(category_id: target_id)
      cat.destroy
    end

    {
      code: 0,
      message: '分类删除成功',
      data: { books_transferred_to: target_id }
    }.to_json
  end

  get '/api/categories/meta/available_parents' do
    exclude_id = params[:exclude_id]
    list = Category.available_parents(exclude_id ? exclude_id.to_i : nil)
    {
      code: 0,
      message: 'success',
      data: list.map { |c|
        {
          id: c.id,
          parent_id: c.parent_id,
          name: c.name,
          level: c.level,
          is_leaf: c.is_leaf
        }
      }
    }.to_json
  end

  post '/api/categories/fix_orphan_books' do
    Category.uncategorized_id
    count = Category.assign_uncategorized_to_orphan_books!

    {
      code: 0,
      message: "已将 #{Book.where(category_id: nil).count} 本图书归入未分类",
      data: { fixed_count: count }
    }.to_json
  end
end
