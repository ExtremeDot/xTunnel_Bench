# xTunnel_Bench

Linux Benchmark
```
curl -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/ExtremeDot/Linux-Bench-/master/bench.sh?$RANDOM" -o bench.sh && chmod +x bench.sh
sudo ./bench.sh
```
----

### Install Script

```
bash <(wget -qO- https://raw.githubusercontent.com/ExtremeDot/xTunnel_Bench/main/frp_manager.sh)
```

یا بصورت نصب در لینوکس و استفاده آفلاین

```
curl -sSL -o /usr/local/bin/frp_manager.sh https://raw.githubusercontent.com/ExtremeDot/xTunnel_Bench/main/frp_manager.sh && chmod +x /usr/local/bin/frp_manager.sh && /usr/local/bin/frp_manager.sh
```

بعد با دستور زیر اجرا کنید

```
frp_manager.sh
```

------

<img width="805" height="664" alt="image" src="https://github.com/user-attachments/assets/7041839d-afc5-43c9-8eb0-3714a21cf093" />


---

اول از گزینه 1 ، فایل های مورد نیاز رو نصب کنید

اول اسکریپت نشون میده که سرور ایران هست یا خارج؟ اگر اشتباه نشون داده شده ، از طریق منوی 8 نوع سرور ایران یا خارج رو تغییر بدید.



بعد سرور ایران رو راه اندازی کنید و در انتها سرور خارج رو راه اندازی کنید

با گزینه 5 ، از وضعیت اتصال مطلع بشید و با گزینه 7 سرعت و کیفیت و پهنای باند اتصال را بررسی کنید.



### Install Dependencies and FRP Binaries

```
1. Install Dependencies & FRP v0.70.1
````


Then Check Server Location to be Correct

Server Location Status: [ KHAREJ ] or Server Location Status: [ IRAN ]
if Wrong change it via Menu:

```
8. Change Location Mode Manually (Toggle Iran/Kharej)
```

---

2- First Setup IRAN 

```
2. Setup FRP Server (Iran - Run on IRAN Server)
```
to generate Authentication Token use command:

```
tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; echo
```

<img width="654" height="464" alt="image" src="https://github.com/user-attachments/assets/b76e189c-5440-4f46-bcea-f24cdee0fdb9" />



---

3-  Setup Kharej Server

```
3. Setup FRP Client (Kharej - Run on KHAREJ Server)
```

<img width="629" height="335" alt="image" src="https://github.com/user-attachments/assets/22ac86b6-63b1-480b-8e76-652fe11ff209" />



-------



