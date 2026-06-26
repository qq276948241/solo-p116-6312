require_relative '../models/init'

class Bookstore < Sinatra::Base
  before '/api/books*' do
    content_type :json, charset: 'utf-8'
  end

  get '/api/books' do
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min

    dataset = Book.search(params.slice(:isbn, :title, :status))
    total = dataset.count
    offset = (page - 1) * per_page

    books = dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all

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
    book = Book[params[:id].to_i]

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
     :condition, :purchase_price, :sale_price, :status, :notes].each do |k|
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
end
