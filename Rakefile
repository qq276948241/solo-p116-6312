require 'rake'
require_relative 'models/init'

namespace :db do
  desc '创建数据库表'
  task :migrate do
    require_relative 'db/migrate'
  end

  desc '重置数据库（先删后建）'
  task :reset do
    ENV['SINATRA_ENV'] ||= 'development'
    db_file = "db/bookstore_#{ENV['SINATRA_ENV']}.db"
    if File.exist?(db_file)
      File.delete(db_file)
      puts "已删除旧数据库: #{db_file}"
    end
    require_relative 'db/migrate'
  end

  desc '填充测试数据'
  task seed: :migrate do
    require 'faker' rescue nil

    puts '开始生成测试数据...'

    conditions = Book::CONDITIONS
    book_titles = [
      ['活着', '余华', '作家出版社', '2012-08-01'],
      ['三体', '刘慈欣', '重庆出版社', '2008-01-01'],
      ['百年孤独', '加西亚·马尔克斯', '南海出版公司', '2011-06-01'],
      ['平凡的世界', '路遥', '北京十月文艺出版社', '2012-03-01'],
      ['围城', '钱钟书', '人民文学出版社', '1991-02-01'],
      ['红楼梦', '曹雪芹', '人民文学出版社', '2008-07-01'],
      ['1984', '乔治·奥威尔', '上海译文出版社', '2011-04-01'],
      ['小王子', '圣埃克苏佩里', '人民文学出版社', '2003-08-01']
    ]

    book_titles.each_with_index do |t, i|
      purchase = (rand(50) + 10).to_f
      Book.create(
        isbn: "97875#{rand(10**8).to_s.rjust(8, '0')}",
        title: t[0],
        author: t[1],
        publisher: t[2],
        publish_date: t[3],
        condition: conditions.sample,
        purchase_price: purchase,
        sale_price: (purchase * (1.5 + rand * 0.5)).round(2),
        status: [Book::AVAILABLE, Book::AVAILABLE, Book::RESERVED].sample
      )
      puts "  已创建图书: #{t[0]}"
    end

    member_names = ['张三', '李四', '王五', '赵六', '陈七', '刘八']
    phones_prefix = ['138', '139', '150', '151', '158', '159']
    member_names.each_with_index do |name, i|
      phone = "#{phones_prefix[i]}#{(10000000 + rand(89999999))}"
      Member.create(
        phone: phone,
        name: name,
        points: rand(500)
      )
      puts "  已创建会员: #{name} (#{phone})"
    end

    puts '测试数据生成完成！'
  end

  desc '清理测试数据'
  task :clean do
    ENV['SINATRA_ENV'] ||= 'development'
    puts '开始清理数据...'
    OrderLog.delete
    OrderItem.delete
    PointsLog.delete
    Order.delete
    Member.delete
    Book.delete
    puts '数据清理完成！'
  end
end

desc '处理超期订单'
task :expire_orders do
  require_relative 'models/init'
  count = Order.expire_overdue!
  puts "已处理 #{count} 笔超期订单"
end

desc '启动应用'
task :server do
  exec 'rackup -p 4567'
end

task default: ['db:migrate', :server]
