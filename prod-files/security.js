angular
    .module('shm_security', [])
    .controller('ShmSecurityController',
        ['$scope', '$location', 'shm_request', function($scope, $location, shm_request) {
        'use strict';

        // State
        $scope.passkeys = [];
        $scope.passkeyEnabled = false;
        $scope.email = '';
        $scope.newEmail = '';
        $scope.newPassword = '';
        $scope.confirmPassword = '';
        $scope.newPasskeyName = '';
        $scope.passwordAuthDisabled = false;
        $scope.otpEnabled = false;
        $scope.loading = true;
        $scope.passkeySupported = !!window.PublicKeyCredential;
        $scope.message = null;
        $scope.messageType = 'success';

        // --- Helpers ---

        $scope.showMessage = function(text, type) {
            $scope.message = text;
            $scope.messageType = type || 'success';
        };

        $scope.clearMessage = function() {
            $scope.message = null;
        };

        // --- Load Data ---

        $scope.loadStatus = function() {
            $scope.loading = true;
            shm_request('GET', 'v1/user/password-auth/status').then(function(response) {
                var data = response.data;
                $scope.passwordAuthDisabled = data.password_auth_disabled;
                $scope.passkeyEnabled = data.passkey_enabled;
                $scope.otpEnabled = data.otp_enabled;
                $scope.email = data.email || '';
                $scope.newEmail = data.email || '';
                $scope.loading = false;
            }, function() {
                $scope.loading = false;
            });
        };

        $scope.loadPasskeys = function() {
            shm_request('GET', 'v1/user/passkey/list').then(function(response) {
                $scope.passkeys = response.data.credentials || [];
                $scope.passkeyEnabled = response.data.enabled;
            });
        };

        // --- Passkey Management ---

        $scope.registerPasskey = function() {
            if (!$scope.passkeySupported) {
                $scope.showMessage('Ваш браузер не поддерживает Passkey', 'danger');
                return;
            }

            shm_request('POST_JSON', 'v1/user/passkey/register/options', {}).then(function(response) {
                var options = response.data;

                var publicKeyOptions = {
                    challenge: _base64urlToBuffer(options.challenge),
                    rp: options.rp,
                    user: {
                        id: _base64urlToBuffer(options.user.id),
                        name: options.user.name,
                        displayName: options.user.displayName
                    },
                    pubKeyCredParams: options.pubKeyCredParams,
                    timeout: options.timeout,
                    attestation: options.attestation || 'none',
                    authenticatorSelection: options.authenticatorSelection || {}
                };

                if (options.excludeCredentials) {
                    publicKeyOptions.excludeCredentials = options.excludeCredentials.map(function(cred) {
                        return {
                            id: _base64urlToBuffer(cred.id),
                            type: cred.type
                        };
                    });
                }

                return navigator.credentials.create({ publicKey: publicKeyOptions });
            }).then(function(credential) {
                var response = {
                    clientDataJSON: _bufferToBase64url(credential.response.clientDataJSON),
                    attestationObject: _bufferToBase64url(credential.response.attestationObject)
                };

                return shm_request('POST_JSON', 'v1/user/passkey/register/complete', {
                    credential_id: _bufferToBase64url(credential.rawId),
                    response: response,
                    name: $scope.newPasskeyName || undefined
                });
            }).then(function() {
                $scope.newPasskeyName = '';
                $scope.showMessage('Passkey успешно добавлен!', 'success');
                $scope.loadPasskeys();
                $scope.loadStatus();
            }, function(error) {
                if (error && error.name === 'NotAllowedError') {
                    $scope.$apply(function() {
                        $scope.showMessage('Регистрация Passkey отменена', 'warning');
                    });
                } else if (error && error.data && error.data.error) {
                    $scope.showMessage('Ошибка: ' + error.data.error, 'danger');
                } else {
                    $scope.$apply(function() {
                        $scope.showMessage('Ошибка регистрации Passkey', 'danger');
                    });
                }
            });
        };

        $scope.deletePasskey = function(credentialId, name) {
            if (!confirm('Удалить Passkey "' + (name || credentialId) + '"?')) return;

            shm_request('POST_JSON', 'v1/user/passkey/delete', {
                credential_id: credentialId
            }).then(function() {
                $scope.showMessage('Passkey удалён', 'success');
                $scope.loadPasskeys();
                $scope.loadStatus();
            }, function(error) {
                $scope.showMessage('Ошибка удаления: ' + (error.data && error.data.error || 'unknown'), 'danger');
            });
        };

        // --- Email Management ---

        $scope.saveEmail = function() {
            $scope.clearMessage();

            if (!$scope.newEmail || !_isValidEmail($scope.newEmail)) {
                $scope.showMessage('Введите корректный email', 'danger');
                return;
            }

            shm_request('POST_JSON', 'v1/user/email', { email: $scope.newEmail }).then(function(response) {
                $scope.email = response.data.email;
                $scope.showMessage('Email сохранён! Теперь вы можете входить через email + пароль.', 'success');
                $scope.loadStatus();
            }, function(error) {
                var msg = error.data && error.data.error || 'Ошибка сохранения email';
                if (msg.indexOf('EMAIL_ALREADY_EXISTS') !== -1) {
                    msg = 'Этот email уже используется другим аккаунтом';
                }
                $scope.showMessage(msg, 'danger');
            });
        };

        // --- Password Management ---

        $scope.changePassword = function() {
            $scope.clearMessage();

            if (!$scope.newPassword) {
                $scope.showMessage('Введите новый пароль', 'danger');
                return;
            }
            if ($scope.newPassword.length < 6) {
                $scope.showMessage('Пароль должен быть не менее 6 символов', 'danger');
                return;
            }
            if ($scope.newPassword !== $scope.confirmPassword) {
                $scope.showMessage('Пароли не совпадают', 'danger');
                return;
            }

            shm_request('POST_JSON', 'v1/user/passwd', { password: $scope.newPassword }).then(function() {
                $scope.newPassword = '';
                $scope.confirmPassword = '';
                $scope.showMessage('Пароль успешно установлен!', 'success');
            }, function(error) {
                $scope.showMessage('Ошибка смены пароля: ' + (error.data && error.data.error || 'unknown'), 'danger');
            });
        };

        // --- WebAuthn Utility Functions ---

        function _base64urlToBuffer(base64url) {
            var base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
            var padding = base64.length % 4;
            if (padding) base64 += '='.repeat(4 - padding);
            var binary = atob(base64);
            var bytes = new Uint8Array(binary.length);
            for (var i = 0; i < binary.length; i++) {
                bytes[i] = binary.charCodeAt(i);
            }
            return bytes.buffer;
        }

        function _bufferToBase64url(buffer) {
            var bytes = new Uint8Array(buffer);
            var binary = '';
            for (var i = 0; i < bytes.length; i++) {
                binary += String.fromCharCode(bytes[i]);
            }
            return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        }

        function _isValidEmail(email) {
            return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
        }

        // --- Init ---

        $scope.loadStatus();
        $scope.loadPasskeys();
    }]);
