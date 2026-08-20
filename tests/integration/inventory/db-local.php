<?php
//тестовое окружение: БД в соседнем контейнере arms-db (см. docker-compose.yml)
return [
	'dsn' => 'mysql:host=arms-db;dbname=arms',
	'username' => 'arms-user',
	'password' => 'arms-password',
];
