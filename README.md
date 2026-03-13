# Zapret2 macOS Native App

Нативное macOS-приложение (Status Bar) для управления [zapret2](https://github.com/bol-van/zapret2). Позволяет обходить DPI и замедления популярных ресурсов (YouTube, Discord, Telegram и др.) прямо из системного трея.

![App Icon](icon.png)

## Основные возможности
*   **Minimalist UI**: Живет в Menu Bar (рядом с часами), не занимает место в Dock.
*   **Passwordless Sudo**: Один раз настраивается доступ, после чего включение/выключение происходит мгновенно без ввода пароля.
*   **Динамические стратегии**: Поддержка JSON-конфигов стратегий, которые можно обновлять "по воздуху".
*   **Flowseal Integration**: В комплекте идут актуальные стратегии от [Flowseal](https://github.com/Flowseal/zapret-discord-youtube).
*   **Native Notifications**: Системные уведомления о статусе работы и обновлениях.
*   **Custom Configs**: Легкое редактирование `hostlist.txt` через папку `~/.zapret2`.

## Установка и запуск
1.  Установите зависимости через Homebrew:
    ```bash
    brew install lua luajit pkg-config
    ```
2.  Скачайте `Zapret2.app` (или соберите из исходников).
3.  Переместите приложение в папку `/Applications` или запустите с Рабочего стола.
4.  В меню приложения выберите **Settings -> Grant Passwordless Access...** и введите пароль администратора один раз.
5.  Нажмите **Start Zapret**.

## Управление стратегиями
Приложение читает список стратегий из файла `~/.zapret2/strategies.json`.
*   **Update from URL**: Вы можете указать прямую ссылку на любой JSON со стратегиями в меню "Add Custom Source URL...".
*   **Flowseal Auto-update**: В корне проекта лежит скрипт `update_from_flowseal.py`. Запустите его (`python3 update_from_flowseal.py`), чтобы автоматически подтянуть самые свежие параметры обхода из репозитория Flowseal в свой `strategies.json`.

## Технические подробности
*   **Движок**: Использует скомпилированный под Darwin бинарник `dvtws2` (BSD-порт nfqws).
*   **Перехват**: Использует системный фаервол `pf` (Packet Filter) и `divert-sockets`.
*   **Язык**: Swift 6 (AppKit), Bash (wrapper).

## Сборка
Если вы хотите собрать приложение самостоятельно:
1.  Установите `xcodegen`: `brew install xcodegen`.
2.  Выполните `xcodegen` в корне проекта.
3.  Откройте `Zapret2Mac.xcodeproj` в Xcode и соберите (Product -> Build).

---
*Разработано с помощью Лизы (Gemini CLI).*
