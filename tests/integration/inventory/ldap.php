<?php
//тестовое окружение: заглушка LDAP (компонент ленивый, в тестах не используется -
//при useRBAC=false авторизация не выполняется вовсе)
return [
	'class' => \app\components\ldap\LdapService::class,
	'connection' => [
		'hosts'    => ['ldap.invalid'],
		'port'     => 636,
		'base_dn'  => 'DC=test,DC=invalid',
		'username' => 'test',
		'password' => 'test',
	],
];
