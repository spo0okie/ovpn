# ovpn
Конфиг и скрипты для управления опенвпном

### Установка:
в папке /etc/openvpn делаем
```bash
git clone https://github.com/spo0okie/ovpn.git .  #скачиваем скрипты
mv _config.sample _config                         #сэмпл кофиг переименовываем в боевой
chmod 755 _reset.sh                               #инициируем инстанс openvpn
```
  
заполняем _config  
выполняем  
  
```bash
_reset.sh
chmod 644 _reset.sh
```
