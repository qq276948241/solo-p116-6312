require_relative '../models/init'

class Bookstore < Sinatra::Base
  before '/api/orders*' do
    content_type :json, charset: 'utf-8'
  end

  get '/api/orders' do
    Order.expire_overdue!

    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min

    dataset = Order.dataset
    if params[:order_no] && !params[:order_no].empty?
      dataset = dataset.where(Sequel.like(:order_no, "%#{params[:order_no]}%"))
    end
    if params[:member_id] && !params[:member_id].empty?
      dataset = dataset.where(member_id: params[:member_id].to_i)
    end
    if params[:status] && !params[:status].empty?
      dataset = dataset.where(status: params[:status])
    end

    total = dataset.count
    offset = (page - 1) * per_page

    orders = dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all

    {
      code: 0,
      message: 'success',
      data: {
        list: orders.map do |o|
          o.serializable_hash(with_items: true, with_member: true)
        end,
        total: total,
        page: page,
        per_page: per_page
      }
    }.to_json
  end

  get '/api/orders/:id' do
    Order.expire_overdue!

    order = Order[params[:id].to_i]

    unless order
      status 404
      return { code: 404, message: '订单不存在', data: nil }.to_json
    end

    {
      code: 0,
      message: 'success',
      data: order.serializable_hash(with_items: true, with_logs: true, with_member: true)
    }.to_json
  end

  post '/api/orders' do
    body = JSON.parse(request.body.read) rescue {}

    book_ids = body['book_ids'] || []
    member_id = body['member_id']
    points_to_use = body['points_to_use'] || 0
    operator = body['operator'] || 'system'

    if book_ids.empty?
      status 422
      return {
        code: 422,
        message: '请选择图书',
        data: nil
      }.to_json
    end

    member = nil
    if member_id
      member = Member[member_id.to_i]
      unless member
        status 422
        return {
          code: 422,
          message: '会员不存在',
          data: nil
        }.to_json
      end
    end

    begin
      order = Order.create_with_items!(
        member: member,
        book_ids: book_ids.uniq.map(&:to_i),
        points_to_use: points_to_use.to_i,
        operator: operator
      )
    rescue => e
      status 422
      return {
        code: 422,
        message: e.message,
        data: nil
      }.to_json
    end

    {
      code: 0,
      message: '订单创建成功',
      data: order.serializable_hash(with_items: true, with_logs: true, with_member: true)
    }.to_json
  end

  patch '/api/orders/:id/confirm' do
    order = Order[params[:id].to_i]

    unless order
      status 404
      return { code: 404, message: '订单不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}
    operator = body['operator'] || 'system'
    remark = body['remark']

    if order.cancelled? || order.expired?
      status 422
      return {
        code: 422,
        message: '订单已取消或已作废，无法确认',
        data: nil
      }.to_json
    end

    order.confirm!(operator: operator, remark: remark)

    {
      code: 0,
      message: '订单确认成功',
      data: order.serializable_hash(with_items: true, with_logs: true)
    }.to_json
  end

  patch '/api/orders/:id/pickup' do
    order = Order[params[:id].to_i]

    unless order
      status 404
      return { code: 404, message: '订单不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}
    operator = body['operator'] || 'system'
    remark = body['remark']

    if order.cancelled? || order.expired?
      status 422
      return {
        code: 422,
        message: '订单已取消或已作废，无法取货',
        data: nil
      }.to_json
    end

    order.pickup!(operator: operator, remark: remark)

    {
      code: 0,
      message: '订单取货成功',
      data: order.serializable_hash(with_items: true, with_logs: true)
    }.to_json
  end

  patch '/api/orders/:id/cancel' do
    order = Order[params[:id].to_i]

    unless order
      status 404
      return { code: 404, message: '订单不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}
    operator = body['operator'] || 'system'
    remark = body['remark']

    if order.picked_up?
      status 422
      return {
        code: 422,
        message: '订单已取货，无法取消',
        data: nil
      }.to_json
    end

    order.cancel!(operator: operator, remark: remark)

    {
      code: 0,
      message: '订单取消成功',
      data: order.serializable_hash(with_items: true, with_logs: true)
    }.to_json
  end

  post '/api/orders/expire_overdue' do
    count = Order.expire_overdue!

    {
      code: 0,
      message: "已处理 #{count} 笔超期订单",
      data: { expired_count: count }
    }.to_json
  end

  get '/api/orders/:id/logs' do
    order = Order[params[:id].to_i]

    unless order
      status 404
      return { code: 404, message: '订单不存在', data: nil }.to_json
    end

    logs = order.order_logs_dataset.order(Sequel.desc(:created_at)).all

    {
      code: 0,
      message: 'success',
      data: logs.map(&:serializable_hash)
    }.to_json
  end

  get '/api/orders/meta/statuses' do
    {
      code: 0,
      message: 'success',
      data: Order::STATUSES.map do |s|
        { key: s, text: Order::STATUS_TEXT[s] }
      end
    }.to_json
  end
end
