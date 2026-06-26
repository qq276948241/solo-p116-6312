require_relative '../models/init'

class Bookstore < Sinatra::Base
  before '/api/members*' do
    content_type :json, charset: 'utf-8'
  end

  get '/api/members' do
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min

    dataset = Member.dataset
    if params[:phone] && !params[:phone].empty?
      dataset = dataset.where(Sequel.like(:phone, "%#{params[:phone]}%"))
    end
    if params[:name] && !params[:name].empty?
      dataset = dataset.where(Sequel.like(:name, "%#{params[:name]}%"))
    end

    total = dataset.count
    offset = (page - 1) * per_page

    members = dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all

    {
      code: 0,
      message: 'success',
      data: {
        list: members.map { |m| m.serializable_hash },
        total: total,
        page: page,
        per_page: per_page
      }
    }.to_json
  end

  get '/api/members/:id' do
    member = Member[params[:id].to_i]

    unless member
      status 404
      return { code: 404, message: '会员不存在', data: nil }.to_json
    end

    with_logs = params[:with_logs] == 'true'
    {
      code: 0,
      message: 'success',
      data: member.serializable_hash(with_logs: with_logs)
    }.to_json
  end

  post '/api/members' do
    body = JSON.parse(request.body.read) rescue {}

    member = Member.new(
      phone: body['phone'],
      name: body['name'],
      points: body['points'] || 0
    )

    unless member.valid?
      status 422
      return {
        code: 422,
        message: '参数错误',
        data: member.errors.full_messages
      }.to_json
    end

    if Member.where(phone: member.phone).count > 0
      status 422
      return {
        code: 422,
        message: '该手机号已注册',
        data: nil
      }.to_json
    end

    member.save

    {
      code: 0,
      message: '会员注册成功',
      data: member.serializable_hash
    }.to_json
  end

  put '/api/members/:id' do
    member = Member[params[:id].to_i]

    unless member
      status 404
      return { code: 404, message: '会员不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}

    update_attrs = {}
    update_attrs[:name] = body['name'] if body.key?('name')
    if body.key?('phone') && body['phone'] != member.phone
      if Member.where(phone: body['phone']).where { id != member.id }.count > 0
        status 422
        return {
          code: 422,
          message: '该手机号已被使用',
          data: nil
        }.to_json
      end
      update_attrs[:phone] = body['phone']
    end

    unless member.update(update_attrs)
      status 422
      return {
        code: 422,
        message: '参数错误',
        data: member.errors.full_messages
      }.to_json
    end

    {
      code: 0,
      message: '更新成功',
      data: member.serializable_hash
    }.to_json
  end

  delete '/api/members/:id' do
    member = Member[params[:id].to_i]

    unless member
      status 404
      return { code: 404, message: '会员不存在', data: nil }.to_json
    end

    if Order.where(member_id: member.id).count > 0
      status 422
      return {
        code: 422,
        message: '该会员已有订单记录，无法删除',
        data: nil
      }.to_json
    end

    PointsLog.where(member_id: member.id).delete
    member.destroy

    {
      code: 0,
      message: '删除成功',
      data: nil
    }.to_json
  end

  get '/api/members/:id/points_logs' do
    member = Member[params[:id].to_i]

    unless member
      status 404
      return { code: 404, message: '会员不存在', data: nil }.to_json
    end

    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 20).to_i
    per_page = [per_page, 100].min
    offset = (page - 1) * per_page

    dataset = PointsLog.where(member_id: member.id)
    if params[:change_type] && !params[:change_type].empty?
      dataset = dataset.where(change_type: params[:change_type])
    end

    total = dataset.count
    logs = dataset.order(Sequel.desc(:created_at)).limit(per_page, offset).all

    {
      code: 0,
      message: 'success',
      data: {
        list: logs.map(&:serializable_hash),
        total: total,
        page: page,
        per_page: per_page
      }
    }.to_json
  end

  post '/api/members/:id/adjust_points' do
    member = Member[params[:id].to_i]

    unless member
      status 404
      return { code: 404, message: '会员不存在', data: nil }.to_json
    end

    body = JSON.parse(request.body.read) rescue {}
    points_change = body['points_change'].to_i
    description = body['description']

    if points_change == 0
      status 422
      return {
        code: 422,
        message: '积分变动数不能为0',
        data: nil
      }.to_json
    end

    if points_change < 0 && points_change.abs > member.points
      status 422
      return {
        code: 422,
        message: "积分不足，当前积分：#{member.points}",
        data: nil
      }.to_json
    end

    DB.transaction do
      member.update(points: member.points + points_change)
      PointsLog.create(
        member_id: member.id,
        points_change: points_change,
        change_type: points_change > 0 ? 'earn' : 'spend',
        description: description || '手动调整积分'
      )
    end

    {
      code: 0,
      message: '积分调整成功',
      data: member.serializable_hash
    }.to_json
  end
end
