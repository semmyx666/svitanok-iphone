# Windows и Fedora: сборка и установка без платной подписки

## Что именно бесплатно, а что всё равно понадобится

| Вариант | Деньги | Что требуется |
|---|---|---|
| Сборка в публичном GitHub-репозитории на стандартном `macos-26` | Бесплатно по текущим условиям GitHub | Бесплатный GitHub-аккаунт, интернет; исходники будут публичными |
| Установка готового IPA на Windows через Sideloadly | Бесплатно по текущим условиям Sideloadly | Apple Account, первоначальное USB-сопряжение, подходящие Apple-компоненты |
| Без платной подписки Apple Developer | Да, основной путь именно такой | Бесплатная подпись обычно действует 7 дней и требует обновления |
| Вообще без Apple Account / любой подходящей подписи | Не предусмотрено | Developer Mode не отменяет подпись |
| Fedora: получение IPA из GitHub Actions | Бесплатно | Браузер либо `gh` + бесплатный GitHub-аккаунт |
| Fedora: самостоятельная подпись/установка | Есть сторонние экспериментальные проекты | Не проверены здесь и на iOS 27.2; не выдаются за готовый путь |
| Уже имеющийся/одолженный Mac вместо GitHub | Нет платы за Xcode | Сам Mac, Apple Account; инструкции в INSTALL_RU.md |

**«Бесплатная подписка» здесь не нужна: GitHub Free и бесплатный Apple Account — аккаунты, не платные подписки.** Оплата Apple Developer Program, TestFlight, VPS, домена и аренды Mac для основной схемы не требуется. При этом бесплатная macOS-сборка GitHub — облачная. Вариант «никакого облака, никакого Mac» этим архивом не обеспечивается.

Я не входил в ваш GitHub, не запускал Actions от вашего имени и не создавал IPA в этой Linux-среде. В ZIP включены реальные команды сборки и упаковки; результат выдаёт только успешный запуск workflow. Если сборка не проходит, скачайте журналы — не устанавливайте пустой файл и не игнорируйте ошибку.

## Часть 1. Windows: получить IPA

### Самый простой путь через браузер

1. Распакуйте `Svitanok-iPhone-v0.2.zip`. Внутри корневой папки `Svitanok` должны быть `project.yml`, `ios`, `scripts`, `server` и **`.github/workflows/build-ios.yml`**.
2. Создайте бесплатный аккаунт https://github.com/ или войдите в свой.
3. Создайте **Public** репозиторий, например `svitanok-iphone`. Не включайте оплату, платные runners или платные тарифы. Исходники и журналы в публичном репозитории доступны другим людям. В комплекте нет ваших паролей/токенов; не добавляйте их сами.
4. В репозитории → Add file → Upload files загрузите **содержимое** `Svitanok`, а не сам ZIP и не лишнюю внешнюю папку. Особенно не пропустите `.github`. Сделайте Commit changes.
5. Откройте Actions → **Build iPhone IPA (unsigned)** → Run workflow. Если Actions отключены, разрешите запуск workflow в своём репозитории. GitHub может потребовать собственную проверку аккаунта; это не повод включать платный тариф.
6. Дождитесь результата. Workflow проверяет Python-тесты, компилирует приложение для симулятора, запускает Swift-тесты, затем собирает ARM64 iPhone-приложение без подписи и упаковывает его.
7. В успешном запуске найдите Artifacts → **Svitanok-unsigned-IPA**. Скачайте и распакуйте artifact ZIP. Внутри должен быть **`Svitanok-unsigned.ipa`**, `SHA256SUMS.txt` и `BUILD_STATUS.txt`.
8. Если запуск красный, IPA не публикуется. Artifacts → **Svitanok-build-logs** содержит журналы. Ошибка/лог — не успешная сборка. После исправления исходников workflow запускают снова.

Workflow запускается вручную, не бесконечно при каждом изменении. Он использует стандартный `macos-26`, не платные `large` / `xlarge`. IPA хранится 3 дня, журналы 1 день. Удаляйте старые artifacts, если часто запускаете сборки: бесплатное хранилище GitHub ограничено и разделяется с другими проектами. Не подключайте платный billing ради этого проекта.

### Тот же путь командами PowerShell

Если предпочитаете команды, установите Git и GitHub CLI:

```powershell
winget install --id Git.Git --exact
winget install --id GitHub.cli --exact
```

После установки откройте новое окно PowerShell. Из папки со скачанным архивом:

```powershell
Expand-Archive .\Svitanok-iPhone-v0.2.zip -DestinationPath .\SvitanokSource
Set-Location .\SvitanokSource\Svitanok

gh auth login --hostname github.com --web --git-protocol https

git init -b main
git add .
git -c user.name="Svitanok Builder" -c user.email="builder@example.invalid" commit -m "Add Svitanok iPhone project"
gh repo create svitanok-iphone --public --source . --remote origin --push

gh workflow run build-ios.yml --ref main
```

`builder@example.invalid` — техническая метка автора коммита, не ваш email, не средство авторизации. GitHub CLI покажет ссылку/код для входа в вашем браузере. Не передавайте код или пароль в чат. Если имя репозитория занято, выберите другое свободное имя вместо `svitanok-iphone`.

Через несколько секунд проверьте запуск:

```powershell
gh run list --workflow build-ios.yml --limit 3
$RunId = gh run list --workflow build-ios.yml --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $RunId --exit-status
gh run download $RunId --name Svitanok-unsigned-IPA --dir .\out
Get-FileHash .\out\Svitanok-unsigned.ipa -Algorithm SHA256
Get-Content .\out\SHA256SUMS.txt
```

Если `$RunId` пустой, дождитесь появления запуска и повторите команды получения ID. Если `watch` сообщает ошибку, вместо IPA скачайте журналы:

```powershell
gh run download $RunId --name Svitanok-build-logs --dir .\build-logs
```

## Часть 2. Windows: бесплатно подписать и поставить IPA

1. Скачайте Windows-версию **только с https://sideloadly.io/**. Это сторонняя программа; прочитайте её условия и оцените доверие до ввода Apple Account.
2. На этой же странице в разделе Before you install установите рекомендованные Apple-компоненты для вашей Windows. Используйте ссылки источника, а не случайные перепакованные iTunes/iCloud.
3. Подключите iPhone к компьютеру USB-кабелем, разблокируйте, подтвердите «Доверять этому компьютеру». Developer Mode у вас уже включён.
4. Запустите Sideloadly, выберите iPhone. Перетащите **`Svitanok-unsigned.ipa`**, не исходный ZIP и не ZIP артефакта.
5. Выберите обычную установку с Apple ID/Apple Account. Введите свой аккаунт **локально в установщике** и подтвердите необходимые проверки Apple. Ни пароль, ни код, ни сертификат не нужны автору проекта, GitHub Secrets или исходникам.
6. Нажмите Start и дождитесь успешной установки. На устройстве, если будет предложено, доверяйте своему профилю разработчика в Settings → General → VPN & Device Management. Не доверяйте случайным корпоративным профилям из интернета.
7. Откройте «Світанок», разрешите системные будильники. Сначала включите **обычный тест через 2 минуты**, заблокируйте экран и дождитесь сигнала. Пока тест не прошёл — не используйте приложение как единственный будильник.
8. Повторите тесты из TEST_PLAN_RU.md. Совместимость установщика именно с iOS 27.2 и конкретным аккаунтом здесь не проверялась. Если Apple/Sideloadly отклоняет установку, сохраните текст ошибки; не меняйте системную дату, не покупайте сомнительные сертификаты и не делайте jailbreak ради прототипа.

### Подпись на 7 дней и Wi-Fi

По документации Sideloadly бесплатная подпись действует 7 дней. Для продолжения использования её обновляют; автообновление требует работающего компьютера, сервисов и доступного телефона. Это **не бесплатное бессрочное разрешение**.

Первое сопряжение — USB. После него Sideloadly описывает обновление/установку по Wi-Fi при одной сети и необходимых Apple/Bonjour-компонентах. Сначала убедитесь, что приложение действительно видно без кабеля и автообновление проходит. Если подписка/профиль истекли, не полагайтесь на будильник до успешного обновления и нового теста.

## Часть 3. «Вообще без подписок» на Windows

**Платных подписок нет в уже описанном пути.** GitHub Free + бесплатный Apple Account + Sideloadly — именно вариант без оплаты.

Если под «без подписок» имеется в виду также **без регистрации, подписи и обновления каждые 7 дней**, такого готового пути для этого IPA на штатном iPhone здесь нет. Архив не содержит enterprise-сертификат, jailbreak, эксплойт, TestFlight-доступ или App Store-публикацию. Не заменяйте отсутствующую подпись переименованием ZIP в IPA.

## Часть 4. Fedora: получить тот же IPA

Через браузер выполняются ровно шаги GitHub из части 1 — ОС вашего ПК для облачной сборки не важна. Или используйте терминал:

```bash
sudo dnf install -y git gh unzip python3
unzip Svitanok-iPhone-v0.2.zip -d SvitanokSource
cd SvitanokSource/Svitanok

gh auth login --hostname github.com --web --git-protocol https
git init -b main
git add .
git -c user.name='Svitanok Builder' -c user.email='builder@example.invalid' commit -m 'Add Svitanok iPhone project'
gh repo create svitanok-iphone --public --source . --remote origin --push
gh workflow run build-ios.yml --ref main
```

Если репозиторий уже создан через Windows, не создавайте второй: клонируйте свой существующий репозиторий через `gh repo clone YOUR_GITHUB_NAME/svitanok-iphone` и перейдите в него.

Через несколько секунд:

```bash
gh run list --workflow build-ios.yml --limit 3
RUN_ID="$(gh run list --workflow build-ios.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID" --exit-status
gh run download "$RUN_ID" --name Svitanok-unsigned-IPA --dir out
(cd out && sha256sum -c SHA256SUMS.txt)
```

Если ID ещё не появился — подождите и повторите. Если сборка красная:

```bash
gh run download "$RUN_ID" --name Svitanok-build-logs --dir build-logs
```

### Установка с Fedora: честные границы

**Sideloadly не выпускает Linux-версию.** Не называйте `wine Sideloadly.exe` проверенным решением: Apple-службы, USB и подпись могут не работать. `ideviceinstaller` сам не создаёт подпись Apple и не превращает unsigned IPA в устанавливаемый файл.

Для вас практический путь без новых покупок: собрать/скачать IPA из Fedora, затем **перезагрузиться в уже имеющуюся Windows** и установить через Sideloadly по части 2. Если используете Windows VM, нужны имеющаяся лицензия/установка и USB passthrough; это здесь не тестировалось, поэтому обычная загрузка вашей Windows предпочтительнее.

Есть сторонний **AltServer-Linux**: https://github.com/NyaMisty/AltServer-Linux . Его README описывает подпись/установку IPA, Apple Account, anisette и дополнительный сетевой компонент для Wi-Fi. Это НЕ проверено здесь на Fedora/iOS 27.2. Кроме того, описанный CLI передаёт пароль в аргументе процесса, а по умолчанию использует внешний anisette-сервис. Поэтому в комплект не включены автоматический запуск этого инструмента, передача ему вашего пароля или «гарантированно работающая» команда. Не используйте основной Apple Account, не изучив реализацию и риски. Самостоятельный эксперимент — не равно готовая надёжная установка.

Для безопасной диагностики USB без передачи Apple-пароля:

```bash
sudo dnf install -y usbmuxd /usr/bin/idevicepair /usr/bin/idevice_id /usr/bin/ideviceinfo
sudo systemctl start usbmuxd
# Подключите и разблокируйте iPhone, подтвердите доверие.
idevicepair pair
idevice_id -l
ideviceinfo -k ProductVersion
```

В команде DNF пакеты утилит выбираются по предоставляемым путям файлов — это не установка пакета из случайного сайта. Доступность зависит от включённых репозиториев вашей Fedora.

Эти команды только сопрягают/читают сведения, **не устанавливают unsigned IPA**. Fedora-only установка этого проекта остаётся неподтверждённой. Это ограничение не скрывается за командами, которые на самом деле ничего не подписывают.

## Часть 5. После установки: тревоги без оплаты VPS

Обычный системный будильник не требует сервера. Статус области и экспериментальный перенос требуют данных API. В `FREE_DATA_PROXY_RU.md` есть сервер на вашем Windows/Fedora и бесплатный временный HTTPS-туннель, без покупки VPS/домена. Нужен выданный вам токен alerts.in.ua. Бесплатность получения/доступность токена и условия источника надо проверить при заявке; токен в комплект не включён.

Не храните API-токен в публичном репозитории. Не выдавайте N/clear за доказательство безопасности. Пока приложение закрыто или iPhone заблокирован, версия 0.2 не гарантирует перенос после отбоя.

## Источники

- Бесплатные стандартные GitHub runners в публичных репозиториях и ограничения хранилища: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Стандартный macOS runner: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- Установка, бесплатный аккаунт, 7 дней и Wi-Fi: https://sideloadly.io/
- Экспериментальная Linux-реализация: https://github.com/NyaMisty/AltServer-Linux
- Apple SDK: https://developer.apple.com/xcode/system-requirements
