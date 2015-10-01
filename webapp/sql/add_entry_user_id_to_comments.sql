ALTER TABLE comments ADD entry_user_id INT NOT NULL ADD INDEX entry_user_id (entry_user_id, created_at);

/home/isucon/.local/ruby/bin/bundle exec ruby add_entry_user_id.rb
```add_entry_user_id.rb
require 'mysql2'
require 'mysql2-cs-bind'

config = {
  db: {
    host: ENV['ISUCON5_DB_HOST'] || 'localhost',
    port: ENV['ISUCON5_DB_PORT'] && ENV['ISUCON5_DB_PORT'].to_i,
    username: ENV['ISUCON5_DB_USER'] || 'root',
    password: ENV['ISUCON5_DB_PASSWORD'],
    database: ENV['ISUCON5_DB_NAME'] || 'isucon5q',
  }
}
db = Mysql2::Client.new(
  host: config[:db][:host],
  port: config[:db][:port],
  username: config[:db][:username],
  password: config[:db][:password],
  database: config[:db][:database],
  reconnect: true,
)

5000.times do |i|
  user_id = i + 1
  query = <<SQL
SELECT id FROM entries WHERE user_id = ?
SQL
  entry_ids = db.xquery(query, user_id).map { |e| e['id'] }
  query = <<SQL
UPDATE comments SET entry_user_id = ? WHERE entry_id IN (?)
SQL
  db.xquery(query, user_id, [entry_ids])
end
```
