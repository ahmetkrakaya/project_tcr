#!/usr/bin/env bash
# Google Play için upload keystore oluşturur.
# Çalıştırdıktan sonra android/key.properties dosyasını düzenleyip
# storePassword, keyPassword ve (isteğe bağlı) storeFile değerlerini girin.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$PROJECT_DIR/android"
KEYSTORE_PATH="$ANDROID_DIR/upload-keystore.jks"
ALIAS="upload"

if [[ -f "$KEYSTORE_PATH" ]]; then
  echo "Hata: $KEYSTORE_PATH zaten mevcut. Silmek istiyorsanız: rm $KEYSTORE_PATH"
  exit 1
fi

echo "Upload keystore oluşturuluyor: $KEYSTORE_PATH"
echo "Sizden şifre ve sertifika bilgileri istenecek; bunları güvenli yerde saklayın."
echo ""

keytool -genkey -v \
  -keystore "$KEYSTORE_PATH" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias "$ALIAS"

echo ""
echo "Keystore oluşturuldu: $KEYSTORE_PATH"
echo ""
echo "Sonraki adımlar:"
echo "1. android/key.properties.example dosyasını android/key.properties olarak kopyalayın"
echo "2. key.properties içinde storePassword ve keyPassword alanlarına az önce girdiğiniz şifreleri yazın"
echo "3. storeFile=upload-keystore.jks (keystore android/ içindeyse bu yeterli)"
echo ""
echo "Örnek key.properties:"
echo "  storePassword=AZ_ÖNCE_GİRDİĞİNİZ_STORE_ŞİFRESİ"
echo "  keyPassword=AZ_ÖNCE_GİRDİĞİNİZ_KEY_ŞİFRESİ"
echo "  keyAlias=$ALIAS"
echo "  storeFile=upload-keystore.jks"
