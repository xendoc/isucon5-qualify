ALTER TABLE comments ADD `entry_user_id` INT NOT NULL,
  ADD `entry_private` tinyint NOT NULL,
  DROP INDEX `created_at`,
  ADD INDEX `entry_user_id_created_at` (`entry_user_id`, `created_at`),
  ADD INDEX `created_at_user_id_entry_private` (`created_at`,`user_id`,`entry_private`);

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
SELECT id, private FROM entries WHERE user_id = ?
SQL
  db.xquery(query, user_id).each do |entry|
    query = <<SQL
UPDATE comments SET entry_user_id = ?, entry_private = ? WHERE entry_id = ?
SQL
    db.xquery(query, user_id, entry['private'], entry['id'])
    end
end
```
