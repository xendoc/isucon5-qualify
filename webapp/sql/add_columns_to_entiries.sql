CREATE TABLE `entries2` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `private` tinyint(4) NOT NULL,
  `title` text,
  `content` text,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `user_id_created_at` (`user_id`,`created_at`),
  KEY `user_id_private_created_at` (`user_id`, `private`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `entries2` (`id`,`user_id`,`private`,`title`,`content`,`created_at`)
SELECT
  e.id,
  e.user_id,
  e.private,
  SUBSTRING(e.body,1,LOCATE('\n',e.body)-1),
  SUBSTRING(e.body,LOCATE('\n',e.body)+1, CHAR_LENGTH(e.body)),
  e.created_at
FROM `entries` AS `e`;
DROP TABLE `entries`;
ALTER TABLE `entries2` RENAME `entries`;
