require_relative '../config/database'

DB.create_table? :categories do
  primary_key :id
  foreign_key :parent_id, :categories
  String :name, size: 100, null: false
  String :code, size: 50
  Integer :level, default: 1, null: false
  Integer :position, default: 0, null: false
  TrueClass :is_leaf, default: true, null: false
  DateTime :created_at
  DateTime :updated_at

  index [:parent_id]
  index [:code], unique: true
  index [:level]
end

DB.create_table? :books do
  primary_key :id
  String :isbn, size: 20
  String :title, size: 255, null: false
  String :author, size: 255
  String :publisher, size: 255
  String :publish_date, size: 50
  String :condition, size: 50, null: false
  Decimal :purchase_price, size: [10, 2], null: false
  Decimal :sale_price, size: [10, 2], null: false
  String :status, size: 20, default: 'available', null: false
  String :notes, text: true
  DateTime :created_at
  DateTime :updated_at

  index [:isbn]
  index [:title]
  index [:status]
end

unless DB[:books].columns.include?(:category_id)
  DB.alter_table :books do
    add_foreign_key :category_id, :categories
    add_index [:category_id]
  end
  puts '已为books表添加 category_id 外键'
end

DB.create_table? :members do
  primary_key :id
  String :phone, size: 20, unique: true, null: false
  String :name, size: 100
  Integer :points, default: 0, null: false
  DateTime :created_at
  DateTime :updated_at

  index [:phone]
end

DB.create_table? :orders do
  primary_key :id
  String :order_no, size: 30, unique: true, null: false
  foreign_key :member_id, :members
  Decimal :total_amount, size: [10, 2], null: false
  Integer :points_used, default: 0
  Integer :points_earned, default: 0
  String :status, size: 20, default: 'pending', null: false
  DateTime :expire_at, null: false
  DateTime :created_at
  DateTime :updated_at

  index [:order_no]
  index [:member_id]
  index [:status]
  index [:expire_at]
end

DB.create_table? :order_items do
  primary_key :id
  foreign_key :order_id, :orders
  foreign_key :book_id, :books
  Decimal :price, size: [10, 2], null: false
  DateTime :created_at

  index [:order_id]
  index [:book_id]
end

DB.create_table? :points_logs do
  primary_key :id
  foreign_key :member_id, :members, null: false
  foreign_key :order_id, :orders
  Integer :points_change, null: false
  String :change_type, size: 20, null: false
  String :description, size: 255
  DateTime :created_at

  index [:member_id]
  index [:order_id]
  index [:change_type]
end

DB.create_table? :order_logs do
  primary_key :id
  foreign_key :order_id, :orders, null: false
  String :from_status, size: 20
  String :to_status, size: 20, null: false
  String :operator, size: 100
  String :remark, size: 255
  DateTime :created_at

  index [:order_id]
end

begin
  if defined?(Category) && Category.where(name: '未分类').count == 0
    Category.create(
      name: '未分类',
      code: 'uncategorized',
      level: 1,
      position: 0,
      is_leaf: true
    )
    puts '已创建兜底分类：未分类'
  end
rescue => e
  puts "兜底分类创建提示：#{e.message}"
end

puts '数据库迁移完成！'
