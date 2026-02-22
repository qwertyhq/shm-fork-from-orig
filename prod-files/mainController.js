angular.module('theme.core.main_controller', ['theme.core.services','ngCookies'])
  .controller('MainController', [
    '$rootScope',
    '$scope',
    '$theme',
    '$timeout',
    'progressLoader',
    'wijetsService',
    '$location',
    '$route',
    '$cookies',
    'shm_request',
    '$window',
    function($rootScope, $scope, $theme, $timeout, progressLoader, wijetsService, $location, $route, $cookies, shm_request, $window ) {
    'use strict';
    $scope.layoutFixedHeader = $theme.get('fixedHeader');
    $scope.layoutPageTransitionStyle = $theme.get('pageTransitionStyle');
    $scope.layoutDropdownTransitionStyle = $theme.get('dropdownTransitionStyle');
    $scope.layoutPageTransitionStyleList = ['bounce',
      'flash',
      'pulse',
      'bounceIn',
      'bounceInDown',
      'bounceInLeft',
      'bounceInRight',
      'bounceInUp',
      'fadeIn',
      'fadeInDown',
      'fadeInDownBig',
      'fadeInLeft',
      'fadeInLeftBig',
      'fadeInRight',
      'fadeInRightBig',
      'fadeInUp',
      'fadeInUpBig',
      'flipInX',
      'flipInY',
      'lightSpeedIn',
      'rotateIn',
      'rotateInDownLeft',
      'rotateInDownRight',
      'rotateInUpLeft',
      'rotateInUpRight',
      'rollIn',
      'zoomIn',
      'zoomInDown',
      'zoomInLeft',
      'zoomInRight',
      'zoomInUp'
    ];

    $scope.user = {};
    $scope.title = $window.env.TITLE;

    $scope.layoutLoading = true;

    $scope.getLayoutOption = function(key) {
      return $theme.get(key);
    };

    $scope.setNavbarClass = function(classname, $event) {
      $event.preventDefault();
      $event.stopPropagation();
      $theme.set('topNavThemeClass', classname);
    };

    $scope.setSidebarClass = function(classname, $event) {
      $event.preventDefault();
      $event.stopPropagation();
      $theme.set('sidebarThemeClass', classname);
    };

    $scope.layoutFixedHeader = $theme.get('fixedHeader');
    $scope.layoutLayoutBoxed = $theme.get('layoutBoxed');
    $scope.layoutLayoutHorizontal = $theme.get('layoutHorizontal');
    $scope.layoutLeftbarCollapsed = $theme.get('leftbarCollapsed');
    $scope.layoutAlternateStyle = $theme.get('alternateStyle');

    $scope.$watch('layoutFixedHeader', function(newVal, oldval) {
      if (newVal === undefined || newVal === oldval) {
        return;
      }
      $theme.set('fixedHeader', newVal);
    });
    $scope.$watch('layoutLayoutBoxed', function(newVal, oldval) {
      if (newVal === undefined || newVal === oldval) {
        return;
      }
      $theme.set('layoutBoxed', newVal);
    });
    $scope.$watch('layoutLayoutHorizontal', function(newVal, oldval) {
      if (newVal === undefined || newVal === oldval) {
        return;
      }
      $theme.set('layoutHorizontal', newVal);
    });
    $scope.$watch('layoutAlternateStyle', function(newVal, oldval) {
      if (newVal === undefined || newVal === oldval) {
        return;
      }
      $theme.set('alternateStyle', newVal);
    });
    $scope.$watch('layoutPageTransitionStyle', function(newVal) {
      $theme.set('pageTransitionStyle', newVal);
    });
    $scope.$watch('layoutDropdownTransitionStyle', function(newVal) {
      $theme.set('dropdownTransitionStyle', newVal);
    });
    $scope.$watch('layoutLeftbarCollapsed', function(newVal, oldVal) {
      if (newVal === undefined || newVal === oldVal) {
        return;
      }
      $theme.set('leftbarCollapsed', newVal);
    });

    $scope.toggleLeftBar = function() {
      $theme.set('leftbarCollapsed', !$theme.get('leftbarCollapsed'));
    };

    $scope.$on('themeEvent:maxWidth767', function(event, newVal) {
      $timeout(function() {
          $theme.set('leftbarCollapsed', newVal);
      });
    });
    $scope.$on('themeEvent:changed:fixedHeader', function(event, newVal) {
      $scope.layoutFixedHeader = newVal;
    });
    $scope.$on('themeEvent:changed:layoutHorizontal', function(event, newVal) {
      $scope.layoutLayoutHorizontal = newVal;
    });
    $scope.$on('themeEvent:changed:layoutBoxed', function(event, newVal) {
      $scope.layoutLayoutBoxed = newVal;
    });
    $scope.$on('themeEvent:changed:leftbarCollapsed', function(event, newVal) {
      $scope.layoutLeftbarCollapsed = newVal;
    });
    $scope.$on('themeEvent:changed:alternateStyle', function(event, newVal) {
      $scope.layoutAlternateStyle = newVal;
    });

    $scope.toggleSearchBar = function($event) {
      $event.stopPropagation();
      $event.preventDefault();
      $theme.set('showSmallSearchBar', !$theme.get('showSmallSearchBar'));
    };

    $scope.toggleExtraBar = function($event) {
      $event.stopPropagation();
      $event.preventDefault();
      $theme.set('extraBarShown', !$theme.get('extraBarShown'));
    };

    $scope.isLoggedIn = false;
    $scope.passkeyAvailable = !!window.PublicKeyCredential;
    $scope.passkeyLoading = false;
    $scope.otpRequired = false;
    $scope.otp_token = '';
    $scope.loginError = '';

    $scope.logOut = function() {
      shm_request('POST', 'user/logout.cgi').then( function(response) {
          $scope.isLoggedIn = false;
          $cookies.remove('session_id');
          $location.path('/extras-login');
      });
    };

    $rootScope.$on('http_401', function (e, data) {
        // Don't auto-logout during OTP flow
        if ( $scope.isLoggedIn ) $scope.logOut();
    });

    $scope.logIn = function() {
      $scope.loginError = '';
      progressLoader.start();
      progressLoader.set(50);

      var params = { login: $scope.login, password: $scope.password };
      if ( $scope.otpRequired && $scope.otp_token ) {
          params.otp_token = $scope.otp_token;
      }

	  shm_request('POST', 'user/auth.cgi', params).then( function(response) {
        var data = response.data;

        // Check if OTP is required (auth.cgi returns HTTP 200 with otp_required in body)
        if ( data.otp_required ) {
            $scope.otpRequired = true;
            $scope.loginError = '';
            progressLoader.end();
            return;
        }

        // Check for error responses (auth.cgi returns status in body, not HTTP status)
        if ( data.msg === 'INVALID_OTP_TOKEN' ) {
            $scope.loginError = 'Неверный код 2FA';
            $scope.otp_token = '';
            progressLoader.end();
            return;
        }

        if ( data.status && data.status !== 200 && !data.session_id ) {
            $scope.loginError = data.msg || 'Неверный логин или пароль';
            $scope.otpRequired = false;
            $scope.otp_token = '';
            progressLoader.end();
            return;
        }

        // Success — got session_id
        if ( data.session_id ) {
            $scope.isLoggedIn = true;
            $scope.otpRequired = false;
            $scope.otp_token = '';
            $scope.loginError = '';
            $location.path('/user_services');
        }
        progressLoader.end();
      }, function(error) {
            $scope.loginError = 'Ошибка подключения к серверу';
            progressLoader.end();
      });
	};

    $scope.loginWithPasskey = function() {
      if (!window.PublicKeyCredential) {
        alert('Ваш браузер не поддерживает Passkey');
        return;
      }

      $scope.passkeyLoading = true;

      shm_request('POST_JSON', 'v1/user/passkey/auth/options/public', {}).then(function(response) {
        var options = response.data;

        var publicKeyOptions = {
          challenge: _base64urlToBuffer(options.challenge),
          timeout: options.timeout,
          rpId: options.rpId,
          userVerification: options.userVerification || 'preferred'
        };

        navigator.credentials.get({ publicKey: publicKeyOptions }).then(function(assertion) {
          $scope.$apply(function() {
            var responseData = {
              clientDataJSON: _bufferToBase64url(assertion.response.clientDataJSON),
              authenticatorData: _bufferToBase64url(assertion.response.authenticatorData),
              signature: _bufferToBase64url(assertion.response.signature),
              userHandle: _bufferToBase64url(assertion.response.userHandle)
            };

            shm_request('POST_JSON', 'v1/user/passkey/auth/public', {
              credential_id: _bufferToBase64url(assertion.rawId),
              response: responseData
            }).then(function(response) {
              if (response.data && response.data.id) {
                $cookies.put('session_id', response.data.id, { expires: new Date(Date.now() + 30 * 24 * 3600 * 1000) });
                $scope.isLoggedIn = true;
                $scope.passkeyLoading = false;
                $location.path('/user_services');
              }
            }, function(error) {
              $scope.passkeyLoading = false;
              if (error && error.data && error.data.error) {
                alert('Ошибка: ' + error.data.error);
              } else {
                alert('Ошибка авторизации через Passkey');
              }
            });
          });
        }).catch(function(err) {
          $scope.$apply(function() {
            $scope.passkeyLoading = false;
          });
          // User cancelled or browser error — silent
        });
      }, function(error) {
        $scope.passkeyLoading = false;
        alert('Ошибка получения параметров Passkey');
      });
    };

    // -- WebAuthn helpers --
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

    $scope.userRegister = function(email, password, confirmPassword) {
      if ( password != confirmPassword ) {
        alert( "Ошибка: Пароли не совпадают!" );
        return;
      }
      shm_request('PUT', '/v1/user', { login: email, password: password } ).then( function(response) {
        $scope.logIn( email, password );
      }, function(error) {
        alert( error.data.error );
      });
    };

    $scope.passwordReset = function(email) {
      shm_request('POST', '/v1/user/passwd/reset', { email: email } ).then( function(response) {
        alert( "Письмо с новым паролем отправлено. Проверьте свою почту." );
        $location.path('/');
      }, function(error) {
        alert( error.data.error );
      });
    };

    $scope.nop = function() {
        shm_request('POST', 'nop.cgi' );
    }

    $scope.sessionCheck = function() {
        var $session_id = $cookies.get('session_id');
        if ($session_id) {
            $scope.isLoggedIn = true;
            return 1;
        }
        return 0;
    };

    $scope.$on('$routeChangeStart', function() {
      var args = $location.search();
      if ( args['partner_id'] ) {
          $cookies.put('partner_id', args['partner_id']);
      }

      if ($location.path() === '/extras-registration') return $location.path();
      if ($location.path() === '/extras-forgotpassword') return $location.path();

      if ( !$scope.sessionCheck() ) return $location.path( '/extras-login' );

      progressLoader.start();
      progressLoader.set(50);
    });

    $scope.$on('$routeChangeSuccess', function() {
      progressLoader.end();
      if ($scope.layoutLoading) {
        $scope.layoutLoading = false;
      }
      // wijetsService.make();
    });
    $scope.change_Theme = function() {
      $theme.change_Theme();
    };
  }]);
