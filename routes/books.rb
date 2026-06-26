require_relative '../models/init'
require_relative '../services/category_service'

class Bookstore < Sinatra::Base
  before '/api/books*' do
    content_type :json, charset: 'utf-8'
  end

  before '/api/categories*' do
    content_type :json, charset: 'utf-8'
  end

  def parse_body
    JSON.parse(request.body.read) rescue {}
  end

  def handle_category_service_error(e)
    case e
    when CategoryService::NotFoundError
      status 404
      { code: 404, message: e.message, data: nil }
    when CategoryService::ProtectedError,
         CategoryService::HasBooksError,
         CategoryService::InvalidParentError,
         CategoryService::Error
      status 422
      { code: 422, message: e.message, data: nil }
    else
      raise e
    end
  end

  # ============ Books ============

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
    body = parse_body

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

    body = parse_body

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

    body = parse_body
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
    body = parse_body
    begin
      book = CategoryService.assign_book_category!(params[:id], body['category_id'])
      {
        code: 0,
        message: '分类设置成功',
        data: book.serializable_hash
      }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
  end

  post '/api/books/categories/batch_assign' do
    body = parse_body
    begin
      result = CategoryService.batch_assign_books!(body['book_ids'], body['category_id'])
      {
        code: 0,
        message: "已批量更新 #{result[:updated_count]} 本图书的分类",
        data: result
      }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
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
    if params[:format] == 'tree'
      data = CategoryService.tree
      { code: 0, message: 'success', data: data }.to_json
    else
      result = CategoryService.list(params)
      { code: 0, message: 'success', data: result }.to_json
    end
  end

  get '/api/categories/tree' do
    data = CategoryService.tree(fix_orphans: true)
    { code: 0, message: 'success', data: data }.to_json
  end

  get '/api/categories/:id' do
    begin
      data = CategoryService.get_detail(
        params[:id],
        with_tree: params[:with_tree] == 'true',
        with_path: params[:with_path] == 'true'
      )
      { code: 0, message: 'success', data: data }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
  end

  get '/api/categories/:id/books' do
    begin
      result = CategoryService.books_for(params[:id], params)
      { code: 0, message: 'success', data: result }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
  end

  post '/api/categories' do
    body = parse_body
    begin
      cat = CategoryService.create!(body)
      { code: 0, message: '分类创建成功', data: cat.serializable_hash }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
  end

  put '/api/categories/:id' do
    body = parse_body
    begin
      cat = CategoryService.update!(params[:id], body)
      { code: 0, message: '分类更新成功', data: cat.serializable_hash }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
  end

  delete '/api/categories/:id' do
    mode = params['mode'] || 'transfer'
    begin
      if mode == 'strict'
        result = CategoryService.delete_strict!(params[:id])
        message = '分类删除成功'
      else
        result = CategoryService.delete_with_transfer!(params[:id], params['transfer_books_to'])
        message = '分类删除成功'
      end
      { code: 0, message: message, data: result }.to_json
    rescue => e
      resp = handle_category_service_error(e)
      resp.to_json
    end
  end

  get '/api/categories/meta/available_parents' do
    list = CategoryService.available_parents(params[:exclude_id])
    { code: 0, message: 'success', data: list }.to_json
  end

  post '/api/categories/fix_orphan_books' do
    result = CategoryService.fix_orphan_books!
    {
      code: 0,
      message: "已将 #{Book.where(category_id: nil).count} 本图书归入未分类",
      data: result
    }.to_json
  end
end
