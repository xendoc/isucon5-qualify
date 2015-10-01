DELETE FROM footprints WHERE id > 500000;
CREATE TABLE `footprints2` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `owner_id` int(11) NOT NULL,
  `date` DATE NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `user_id_created_at` (`user_id`,`created_at`),
  UNIQUE `user_id_owner_id_date` (`user_id`, `owner_id`, `date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
INSERT INTO `footprints2` (`id`,`user_id`,`owner_id`,`date`,`created_at`)
SELECT
  f.id,
  f.user_id,
  f.owner_id,
  DATE(f.created_at) AS date,
  MAX(f.created_at) AS updated
FROM footprints f
GROUP BY user_id, owner_id, DATE(created_at);
DROP TABLE `footprints`;
ALTER TABLE `footprints2` RENAME `footprints`;

# TODO initialize
# DELETE FROM footprints WHERE id > 499995;
