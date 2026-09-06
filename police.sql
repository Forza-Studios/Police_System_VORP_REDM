CREATE TABLE IF NOT EXISTS `gw_police_records` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `charidentifier` varchar(100) NOT NULL,
  `firstname` varchar(100) DEFAULT NULL,
  `lastname` varchar(100) DEFAULT NULL,
  `officer_name` varchar(200) DEFAULT NULL,
  `title` varchar(255) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `charges` text DEFAULT NULL,
  `jail_time` int(11) DEFAULT 0,
  `jail_location` varchar(50) DEFAULT 'None',
  `date` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gw_police_warrants` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `charidentifier` varchar(100) NOT NULL,
  `firstname` varchar(100) DEFAULT NULL,
  `lastname` varchar(100) DEFAULT NULL,
  `reason` text DEFAULT NULL,
  `issuer` varchar(200) DEFAULT NULL,
  `char_img` text DEFAULT NULL,
  `date` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gw_jail` (
  `charidentifier` varchar(100) NOT NULL,
  `jail_time` int(11) DEFAULT 0,
  `jail_location` varchar(50) DEFAULT 'Valentine',
  PRIMARY KEY (`charidentifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
