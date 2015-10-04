require 'sinatra/base'
require 'mysql2'
require 'mysql2-cs-bind'
require 'tilt/erubis'
require 'erubis'
require 'redis'
require './users.rb'
require 'rack-mini-profiler' if ENV['RACK_ENV'] == 'development'

module Isucon5
  class AuthenticationError < StandardError; end
  class PermissionDenied < StandardError; end
  class ContentNotFound < StandardError; end
  module TimeWithoutZone
    def to_s
      strftime("%F %H:%M:%S")
    end
  end
  ::Time.prepend TimeWithoutZone
end

class Isucon5::WebApp < Sinatra::Base
  use Rack::MiniProfiler if ENV['RACK_ENV'] == 'development'
  use Rack::Session::Cookie,
    coder: Class.new {
      def encode(str)
        ::Marshal.dump(str)
      end
      def decode(str)
        return unless str
        ::Marshal.load(str) rescue nil
      end
    }.new
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../../static', __FILE__)
  set :protection, true

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISUCON5_DB_HOST'] || 'localhost',
          port: ENV['ISUCON5_DB_PORT'] && ENV['ISUCON5_DB_PORT'].to_i,
          username: ENV['ISUCON5_DB_USER'] || 'root',
          password: ENV['ISUCON5_DB_PASSWORD'],
          database: ENV['ISUCON5_DB_NAME'] || 'isucon5q',
          socket: ENV['RACK_ENV'] == 'development' ? '/tmp/mysql.sock' : '/var/run/mysqld/mysqld.sock'
        },
        kvs: {
          path: '/tmp/redis.sock'
        }
      }
    end

    def db
      return Thread.current[:isucon5_db] if Thread.current[:isucon5_db]
      client = Mysql2::Client.new(
        #host: config[:db][:host],
        #port: config[:db][:port],
        socket: config[:db][:socket],
        username: config[:db][:username],
        password: config[:db][:password],
        database: config[:db][:database],
        reconnect: true,
      )
      client.query_options.merge!(symbolize_keys: true)
      Thread.current[:isucon5_db] = client
      client
    end

    def kvs
      @redis ||= Redis.new(path: config[:kvs][:path], driver: :hiredis)
    end

    def authenticate(email, password)
      raise Isucon5::AuthenticationError unless USER_EMAILS[email]
      raise Isucon5::AuthenticationError unless USERS[USER_EMAILS[email]][4] == hash(password, USERS[USER_EMAILS[email]][5])
      session[:user_id] = USERS[USER_EMAILS[email]][0]
      {
        id: USERS[USER_EMAILS[email]][0],
        account_name: USERS[USER_EMAILS[email]][1],
        nick_name: USERS[USER_EMAILS[email]][2],
        email: USERS[USER_EMAILS[email]][3]
      }
    end

    def hash(password, salt)
      Digest::SHA512.hexdigest("#{password}#{salt}")
    end

    def current_user
      return @user if @user
      unless session[:user_id]
        return nil
      end
      @user = {
        id: USERS[USER_IDS[session[:user_id]]][0],
        account_name: USERS[USER_IDS[session[:user_id]]][1],
        nick_name: USERS[USER_IDS[session[:user_id]]][2],
        email: USERS[USER_IDS[session[:user_id]]][3]
      }
      unless @user
        session[:user_id] = nil
        session.clear
        raise Isucon5::AuthenticationError
      end
      @user
    end

    def authenticated!
      redirect '/login' unless current_user
    end

    def get_user(user_id)
      raise Isucon5::ContentNotFound unless USER_IDS[user_id]
      {
        id: USERS[USER_IDS[user_id]][0],
        account_name: USERS[USER_IDS[user_id]][1],
        nick_name: USERS[USER_IDS[user_id]][2],
        email: USERS[USER_IDS[user_id]][3],
        passhash: USERS[USER_IDS[user_id]][4]
      }
    end

    def user_from_account(account_name)
      raise Isucon5::ContentNotFound unless USERS[account_name]
      {
        id: USERS[account_name][0],
        account_name: USERS[account_name][1],
        nick_name: USERS[account_name][2],
        email: USERS[account_name][3],
        passhash: USERS[account_name][4]
      }
    end

    def is_friend?(another_id)
      return false unless session[:user_id]
      get_friends unless @friends
      @friends.include?(another_id.to_s)
    end

    def get_friends
      @friends ||= kvs.hkeys("relations:#{session[:user_id]}")
    end

    def is_friend_account?(account_name)
      is_friend?(user_from_account(account_name)[:id])
    end

    def permitted?(another_id)
      another_id == current_user[:id] || is_friend?(another_id)
    end

    def mark_footprint(user_id)
      if user_id != current_user[:id]
        kvs.del("html:footprints:#{user_id}")
        kvs.zadd("footprints:sorted:#{user_id}", Time.now.to_i, current_user[:id])
      end
    end

    PREFS = %w(
      未入力
      北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 新潟県 富山県
      石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 奈良県 和歌山県 鳥取県 島根県
      岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県
    )
    def prefectures
      PREFS
    end
  end

  error Isucon5::AuthenticationError do
    session[:user_id] = nil
    halt 401, erubis(:login, layout: false, locals: { message: 'ログインに失敗しました' })
  end

  error Isucon5::PermissionDenied do
    halt 403, erubis(:error, locals: { message: '友人のみしかアクセスできません' })
  end

  error Isucon5::ContentNotFound do
    halt 404, erubis(:error, locals: { message: '要求されたコンテンツは存在しません' })
  end

  get '/login' do
    session.clear
    erb :login, layout: false, locals: { message: '高負荷に耐えられるSNSコミュニティサイトへようこそ!' }
  end

  post '/login' do
    authenticate params['email'], params['password']
    redirect '/'
  end

  get '/logout' do
    session[:user_id] = nil
    session.clear
    redirect '/login'
  end

  get '/' do
    authenticated!
    html = kvs.get("html:index:#{current_user[:id]}")
    return html if html
    profile = db.xquery('SELECT * FROM profiles WHERE user_id = ?', current_user[:id]).first
    entries_query = 'SELECT id,title FROM entries WHERE user_id = ? ORDER BY created_at LIMIT 5'
    entries = db.xquery(entries_query, current_user[:id]).map do |entry|
      entry[:is_private] = (entry[:private] == 1)
      entry
    end

    comments_for_me_query = <<SQL
SELECT user_id,comment,created_at
FROM comments
WHERE entry_user_id = ?
ORDER BY created_at DESC
LIMIT 10
SQL
    comments_for_me = db.xquery(comments_for_me_query, current_user[:id])

    entries_of_friends_query = <<SQL
SELECT id,user_id,title,created_at
FROM entries
WHERE user_id IN (?)
ORDER BY created_at DESC
LIMIT 10
SQL
    entries_of_friends = db.xquery(entries_of_friends_query, [get_friends])

    comments_of_friends = []
    public_comments_of_friends_query = <<SQL
SELECT id,user_id,entry_id,entry_user_id,comment,created_at,entry_private AS private
FROM comments
WHERE user_id in (?)
AND entry_private = 0
ORDER BY created_at DESC
LIMIT 10
SQL
    tmp_comments_of_friends = db.xquery(public_comments_of_friends_query, [get_friends]).to_a
    private_comments_of_friends_query = <<SQL
    SELECT id,user_id,entry_id,entry_user_id,comment,created_at,entry_private AS private
FROM comments
WHERE user_id in (?)
AND entry_private = 1
ORDER BY created_at DESC
LIMIT 10
SQL
    tmp_comments_of_friends.concat db.xquery(private_comments_of_friends_query, [get_friends]).to_a
    tmp_comments_of_friends.sort_by { |c| c[:created_at] }.reverse.each do |comment|
      next if comment[:private] == 1 && !permitted?(comment[:entry_user_id])
      comments_of_friends << comment
      break if comments_of_friends.size >= 10
    end

    friends = get_friends

    footprints = kvs.zrevrange("footprints:sorted:#{current_user[:id]}", 0, 9, with_scores: true)

    locals = {
      profile: profile || {},
      entries: entries,
      comments_for_me: comments_for_me,
      entries_of_friends: entries_of_friends,
      comments_of_friends: comments_of_friends,
      friends: friends,
      footprints: footprints
    }
    html = erb(:index, locals: locals)
    kvs.setex("html:index:#{current_user[:id]}", 1, html)
    html
  end

  # cache
  get '/profile/:account_name' do
    authenticated!
    owner = user_from_account(params['account_name'])
    prof = db.xquery('SELECT * FROM profiles WHERE user_id = ?', owner[:id]).first || {}
    permitted = permitted?(owner[:id])

    query = if permitted
              'SELECT * FROM entries WHERE user_id = ? ORDER BY created_at LIMIT 5'
            else
              'SELECT * FROM entries WHERE user_id = ? AND private=0 ORDER BY created_at LIMIT 5'
            end
    entries = db.xquery(query, owner[:id]).map do |entry|
      entry[:is_private] = (entry[:private] == 1)
      entry
    end
    mark_footprint(owner[:id])
    erb :profile, locals: { owner: owner, profile: prof, entries: entries, private: permitted }
  end

  # destroy cache '/', '/profile/:account_name'
  post '/profile/:account_name' do
    authenticated!
    raise Isucon5::PermissionDenied if params['account_name'] != current_user[:account_name]
    args = [current_user[:id], params['first_name'], params['last_name'], params['sex'], params['birthday'], params['pref']]
    query = <<SQL
REPLACE INTO profiles (user_id, first_name, last_name, sex, birthday, pref, updated_at)
VALUES (?,?,?,?,?,?,CURRENT_TIMESTAMP())
SQL
    db.xquery(query, *args)
    redirect "/profile/#{params['account_name']}"
  end

  get '/diary/entries/:account_name' do
    authenticated!
    owner = user_from_account(params['account_name'])
    query = if permitted?(owner[:id])
              'SELECT * FROM entries WHERE user_id = ? ORDER BY created_at DESC LIMIT 20'
            else
              'SELECT * FROM entries WHERE user_id = ? AND private=0 ORDER BY created_at DESC LIMIT 20'
            end
    entries = db.xquery(query, owner[:id]).map do |entry|
      entry[:is_private] = (entry[:private] == 1)
      entry
    end
    query = <<SQL
SELECT entry_id, COUNT(*) AS cnt FROM comments WHERE entry_id IN (?) GROUP BY entry_id
SQL
    counts = db.xquery(query, [ entries.map { |e| e[:id] } ]).map { |row| [row[:entry_id], row[:cnt]] }.to_h
    mark_footprint(owner[:id])
    erb :entries, locals: { owner: owner, entries: entries, counts: counts, myself: (current_user[:id] == owner[:id]) }
  end

  get '/diary/entry/:entry_id' do
    authenticated!
    cache = kvs.hgetall("html:entry:#{params['entry_id']}")
    unless cache.empty?
      mark_footprint(cache['owner_id'])
      return cache['html']
    end
    entry = db.xquery('SELECT * FROM entries WHERE id = ?', params['entry_id']).first
    raise Isucon5::ContentNotFound unless entry
    owner = get_user(entry[:user_id])
    entry[:is_private] = (entry[:private] == 1)
    raise Isucon5::PermissionDenied if entry[:is_private] && !permitted?(owner[:id])
    comments = db.xquery('SELECT * FROM comments WHERE entry_id = ?', entry[:id])
    mark_footprint(owner[:id])
    html = erb(:entry, locals: { owner: owner, entry: entry, comments: comments })
    unless entry[:is_private]
      kvs.hmset("html:entry:#{params['entry_id']}", ['html', html, 'owner_id', owner[:id]])
    end
    html
  end

  post '/diary/entry' do
    authenticated!
    query = 'INSERT INTO entries (user_id, private, title, content) VALUES (?,?,?,?)'
    db.xquery(query, current_user[:id], (params['private'] ? '1' : '0'), (params['title'] || "タイトルなし"), params['content'])
    redirect "/diary/entries/#{current_user[:account_name]}"
  end

  post '/diary/comment/:entry_id' do
    authenticated!
    entry = db.xquery('SELECT * FROM entries WHERE id = ?', params['entry_id']).first
    raise Isucon5::ContentNotFound unless entry
    entry[:is_private] = (entry[:private] == 1)
    raise Isucon5::PermissionDenied if entry[:is_private] && !permitted?(entry[:user_id])
    query = 'INSERT INTO comments (entry_id, user_id, entry_user_id, entry_private, comment) VALUES (?,?,?,?,?)'
    db.xquery(query, entry[:id], current_user[:id], entry[:user_id], entry[:private], params['comment'])
    unless entry[:is_private]
      kvs.del("html:entry:#{params['entry_id']}")
    end
    redirect "/diary/entry/#{entry[:id]}"
  end

  get '/footprints' do
    authenticated!
    html = kvs.get("html:footprints:#{current_user[:id]}")
    return html if html
    footprints = kvs.zrevrange("footprints:sorted:#{current_user[:id]}", 0, 49, with_scores: true)
    html = erb(:footprints, locals: { footprints: footprints })
    kvs.set("html:footprints:#{current_user[:id]}", html)
    html
  end

  get '/friends' do
    authenticated!
    html = kvs.get("html:friends:#{current_user[:id]}")
    return html if html
    list = []
    kvs.hgetall("relations:#{current_user[:id]}").each do |user_id, created_at|
      list.unshift([user_id.to_i, Time.at(created_at.to_i).strftime('%F %T')])
    end
    html = erb(:friends, locals: { friends: list })
    kvs.set("html:friends:#{current_user[:id]}", html)
    html
  end

  post '/friends/:account_name' do
    authenticated!
    unless is_friend_account?(params['account_name'])
      user = user_from_account(params['account_name'])
      raise Isucon5::ContentNotFound unless user
      t = Time.now.to_i
      kvs.hset("relations:#{current_user[:id]}", user[:id], t)
      kvs.del("html:friends:#{current_user[:id]}")
      kvs.hset("relations:#{user[:id]}", current_user[:id], t)
      kvs.del("html:friends:#{user[:id]}")
      redirect '/friends'
    end
  end

  get '/initialize' do
    kvs.flushall
    # init friends
    db.query("DELETE FROM relations WHERE id > 500000")
    USER_IDS.keys.each do |id|
      # 古い順で取得
      query = 'SELECT another,created_at FROM relations WHERE one = ? ORDER BY created_at ASC'
      list = []
      db.xquery(query, id).each { |row| list.push row[:another], row[:created_at].to_i }
      kvs.hmset("relations:#{id}", list)

      # html cache
      list = []
      kvs.hgetall("relations:#{id}").each do |user_id, created_at|
        list.unshift([user_id.to_i, Time.at(created_at.to_i).strftime('%F %T')])
      end
      kvs.set("html:friends:#{id}", erb(:friends, locals: { friends: list }))
    end
    db.query("DELETE FROM footprints WHERE id > 500000")
    USER_IDS.keys.each do |id|
      # 過去のデータは利用しないのでLIMIT50で十分
      query = <<SQL
SELECT user_id, owner_id, date, created_at as updated
FROM footprints
WHERE user_id = ?
GROUP BY user_id, owner_id, date
ORDER BY created_at DESC
LIMIT 50
SQL
      list = []
      db.xquery(query, id).each { |row| list.push row[:updated].to_i, row[:owner_id] }
      kvs.zadd("footprints:sorted:#{id}", list)
    end
    db.query("DELETE FROM entries WHERE id > 500000")
    db.query("DELETE FROM comments WHERE id > 1500000")
  end
end
