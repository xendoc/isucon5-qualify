ALTER TABLE entries DROP INDEX `user_id`, DROP INDEX `created_at`, ADD INDEX `created_at_user_id` (`created_at`, `user_id`);
ALTER TABLE comments DROP INDEX `entry_user_id`, DROP INDEX `created_at`, ADD INDEX `created_at_user_id` (created_at, user_id), ADD INDEX `created_at_entry_user_id` (created_at, entry_user_id);
