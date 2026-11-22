# .gitignore

Danh sách các file và thư mục Git bỏ qua trong repo, kèm lý do.

## Python
| Mẫu | Ý nghĩa |
|---|---|
| `.venv/` | Môi trường ảo Python, sinh lại bằng `python -m venv .venv` |
| `__pycache__/` | Thư mục bytecode đã biên dịch |
| `*.pyc` | File bytecode Python |
| `.pytest_cache/` | Bộ nhớ đệm của pytest |

## Kết quả chạy test
Sinh lại bằng `run_tests.ps1`.

| Mẫu | Ý nghĩa |
|---|---|
| `ket_qua/` | Thư mục kết quả test theo từng lần chạy |
| `ket_qua_test.txt` | File tóm tắt kết quả test |

## Mật khẩu demo dạng rõ
Sinh bằng `demo_app/scripts/create_demo_accounts.py`. Không đưa lên Git vì chứa mật khẩu chưa băm.

| Mẫu | Ý nghĩa |
|---|---|
| `demo_app/DEMO_ACCOUNTS.md` | Email và mật khẩu gốc của tài khoản demo |
| `.env` | Biến môi trường cục bộ (`DATABASE_URL`, `SECRET_KEY`) |

## Windows / IDE
| Mẫu | Ý nghĩa |
|---|---|
| `*.lnk` | Shortcut của Windows |
| `.idea/` | Cấu hình JetBrains IDE |
| `.vscode/` | Cấu hình Visual Studio Code |

## Nội dung gốc

```gitignore
# Python
.venv/
__pycache__/
*.pyc
.pytest_cache/

# Kết quả chạy test (sinh lại bằng run_tests.ps1)
ket_qua/
ket_qua_test.txt

# Mật khẩu demo dạng rõ (sinh bằng demo_app/scripts/create_demo_accounts.py)
demo_app/DEMO_ACCOUNTS.md
.env

# Windows / IDE
*.lnk
.idea/
.vscode/
```
