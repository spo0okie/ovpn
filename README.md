# ovpn
Конфиг и скрипты для управления опенвпном

### Установка:
в папке /etc/openvpn делаем
```bash
git clone https://github.com/spo0okie/ovpn.git .  #скачиваем скрипты
mv _config.sample _config                         #сэмпл кофиг переименовываем в боевой
chmod 755 _reset.sh                               #разрешаем инициировать инстанс openvpn
```
  
заполняем _config  
заполняем openssl.cfg (по желанию)
выполняем  
  
```bash
_reset.sh                                         #инициируем инстанс openvpn
chmod 644 _reset.sh                               #защищаемся от переинициализации боевого инстанса
```

### создать пользователя
```bash
usr.new username
```
конфиг пользователя кладется в /users/prefix_username/prefix_username.ovpn
таким же образом можно обновить пользователя

### Обход всех пользователей
Пример пересборки CCD файла
```bash
for f in ./clients/prefix-*; do rm -f $f/ccd; $f/_renew; done
```
