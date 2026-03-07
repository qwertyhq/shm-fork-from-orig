<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
    <meta name="format-detection" content="telephone=no"/>
    <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
    <meta name="MobileOptimized" content="176"/>
    <meta name="HandheldFriendly" content="True"/>
    <meta name="robots" content="noindex,nofollow"/>
    <title></title>
    <script src="https://telegram.org/js/telegram-web-app.js?1"></script>
    <style>
        /* Убираем отступы и задаём 100% ширину и высоту для html и body */
        html, body {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            overflow-x: hidden;
        }
        
        body {
            --bg-color: var(--tg-theme-bg-color, #ffffff);
            --card-bg: var(--tg-theme-secondary-bg-color, #f8f9fa);
            --accent-color: #4ade80;
            --accent-hover: #22c55e;
            --text-primary: var(--tg-theme-text-color, #000000);
            --text-secondary: var(--tg-theme-hint-color, #6b7280);
            --border-color: var(--tg-theme-section-separator-color, #e5e7eb);
            --error-color: #ef4444;
            --success-color: #10b981;
            --button-color: var(--accent-color);
            --button-text-color: #000000;
            --input-bg-color: rgba(255, 255, 255, 0.05);
            --input-border-color: var(--border-color);
            --input-text-color: var(--text-primary);
            
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-color);
            color: var(--text-primary);
            font-size: 16px;
            min-height: 100vh;
            color-scheme: var(--tg-color-scheme);
            line-height: 1.6;
            position: relative;
        }

        /* Animated background particles */
        .bg-particles {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            pointer-events: none;
            z-index: 0;
            overflow: hidden;
        }

        .particle {
            position: absolute;
            width: 4px;
            height: 4px;
            background: var(--accent-color);
            border-radius: 50%;
            opacity: 0.1;
            animation: float 6s ease-in-out infinite;
        }

        @keyframes float {
            0%, 100% { transform: translateY(0px) rotate(0deg); opacity: 0.1; }
            50% { transform: translateY(-20px) rotate(180deg); opacity: 0.3; }
        }

        .main-container {
            padding: 24px 20px;
            max-width: 400px;
            margin: 0 auto;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            gap: 24px;
            position: relative;
            z-index: 1;
        }

        .header {
            text-align: center;
            margin-bottom: 8px;
            transform: translateY(20px);
            opacity: 0;
            animation: slideInFade 0.8s ease-out 0.2s forwards;
        }

        .header-icon {
            width: 64px;
            height: 64px;
            background: linear-gradient(135deg, var(--accent-color), var(--accent-hover));
            border-radius: 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 16px;
            font-size: 28px;
            box-shadow: 0 8px 32px rgba(74, 222, 128, 0.3);
            transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            animation: pulse 2s ease-in-out infinite;
            cursor: pointer;
        }

        .header-icon:hover {
            transform: scale(1.1) rotate(5deg);
            box-shadow: 0 12px 40px rgba(74, 222, 128, 0.5);
        }

        @keyframes pulse {
            0%, 100% { box-shadow: 0 8px 32px rgba(74, 222, 128, 0.3); }
            50% { box-shadow: 0 12px 40px rgba(74, 222, 128, 0.5); }
        }

        h2 {
            font-size: 28px;
            font-weight: 700;
            text-align: center;
            margin: 0 0 8px 0;
            background: linear-gradient(135deg, var(--text-primary), var(--accent-color));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }

        h4 {
            font-size: 16px;
            font-weight: 600;
            margin: 0 0 12px 0;
            color: var(--text-primary);
            transition: color 0.3s ease;
        }

        .form-card {
            background: var(--card-bg);
            border-radius: 20px;
            padding: 24px;
            border: 1px solid var(--border-color);
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.05);
            backdrop-filter: blur(10px);
            transform: translateY(30px);
            opacity: 0;
            animation: slideInFade 0.8s ease-out 0.4s forwards;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }

        .form-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 2px;
            background: linear-gradient(90deg, transparent, var(--accent-color), transparent);
            animation: shimmer 3s ease-in-out infinite;
        }

        @keyframes shimmer {
            0% { left: -100%; }
            50% { left: 100%; }
            100% { left: 100%; }
        }

        .form-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }

        .input-wrapper {
            position: relative;
            margin-bottom: 20px;
        }

        .input-wrapper::after {
            content: '';
            position: absolute;
            bottom: 2px;
            left: 50%;
            width: 0;
            height: 2px;
            background: linear-gradient(90deg, var(--accent-color), var(--accent-hover));
            transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            transform: translateX(-50%);
            border-radius: 0 0 10px 10px;
        }

        .input-wrapper.focused::after {
            width: calc(100% - 8px);
        }

        .input-label {
            position: absolute;
            left: 20px;
            top: 50%;
            transform: translateY(-50%);
            color: var(--text-secondary);
            font-size: 16px;
            font-weight: 400;
            transition: all 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);
            pointer-events: none;
            background: transparent;
            padding: 0 4px;
            z-index: 2;
            transform-origin: left center;
        }

        .input-label.active {
            top: -14px;
            left: 12px;
            transform: translateY(0) scale(0.75);
            color: var(--accent-color);
            font-weight: 600;
            background: var(--card-bg);
            padding: 2px 8px;
            border-radius: 6px;
            box-shadow: 0 2px 8px rgba(74, 222, 128, 0.2);
        }

        input[type="number"],
        input[type="email"] {
            font-size: 16px;
            padding: 18px 20px;
            border: 2px solid var(--input-border-color);
            background-color: var(--input-bg-color);
            border-radius: 12px;
            color: var(--input-text-color);
            width: 100%;
            box-sizing: border-box;
            font-weight: 500;
            transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            backdrop-filter: blur(10px);
            position: relative;
            z-index: 1;
        }

        input[type="number"]:focus,
        input[type="email"]:focus {
            outline: none;
            border-color: var(--accent-color);
            box-shadow: 
                0 0 0 4px rgba(74, 222, 128, 0.1),
                0 4px 20px rgba(74, 222, 128, 0.15);
            background-color: rgba(255, 255, 255, 0.08);
            transform: scale(1.02) translateY(-1px);
        }

        input[type="number"]:not(:placeholder-shown),
        input[type="email"]:not(:placeholder-shown) {
            border-color: var(--accent-color);
            background-color: rgba(74, 222, 128, 0.05);
        }

        input[type="number"]:focus + .input-label,
        input[type="email"]:focus + .input-label,
        input[type="number"]:not(:placeholder-shown) + .input-label,
        input[type="email"]:not(:placeholder-shown) + .input-label {
            top: -14px;
            left: 12px;
            transform: translateY(0) scale(0.75);
            color: var(--accent-color);
            font-weight: 600;
            background: var(--card-bg);
            padding: 2px 8px;
            border-radius: 6px;
            box-shadow: 0 2px 8px rgba(74, 222, 128, 0.2);
        }

        /* Индикатор валидации */
        .input-validation {
            position: absolute;
            right: 16px;
            top: 50%;
            transform: translateY(-50%) scale(0.8);
            font-size: 16px;
            opacity: 0;
            transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
            font-weight: 600;
        }

        .input-validation.valid {
            opacity: 1;
            color: var(--success-color);
            transform: translateY(-50%) scale(1);
            animation: bounceIn 0.5s ease-out;
        }

        .input-validation.invalid {
            opacity: 1;
            color: var(--error-color);
            transform: translateY(-50%) scale(1);
            animation: shake 0.4s ease-in-out;
        }

        @keyframes bounceIn {
            0% { transform: translateY(-50%) scale(0.3); opacity: 0; }
            50% { transform: translateY(-50%) scale(1.05); }
            70% { transform: translateY(-50%) scale(0.9); }
            100% { transform: translateY(-50%) scale(1); opacity: 1; }
        }

        @keyframes shake {
            0%, 100% { transform: translateY(-50%) translateX(0) scale(1); }
            25% { transform: translateY(-50%) translateX(-2px) scale(1); }
            75% { transform: translateY(-50%) translateX(2px) scale(1); }
        }

        .payment-methods {
            background: var(--card-bg);
            border-radius: 20px;
            padding: 24px;
            border: 1px solid var(--border-color);
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.05);
            backdrop-filter: blur(10px);
            transform: translateY(30px);
            opacity: 0;
            animation: slideInFade 0.8s ease-out 0.6s forwards;
            position: relative;
            overflow: hidden;
        }

        .payment-methods::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 2px;
            background: linear-gradient(90deg, transparent, var(--accent-color), transparent);
            animation: shimmer 3s ease-in-out infinite 1s;
        }

        .button-container {
            display: flex;
            gap: 12px;
            margin-bottom: 12px;
            align-items: center;
            transform: translateX(-20px);
            opacity: 0;
            animation: slideInFromLeft 0.6s ease-out forwards;
        }

        .button-container:nth-child(2) { animation-delay: 0.1s; }
        .button-container:nth-child(3) { animation-delay: 0.2s; }
        .button-container:nth-child(4) { animation-delay: 0.3s; }

        @keyframes slideInFromLeft {
            from {
                transform: translateX(-20px);
                opacity: 0;
            }
            to {
                transform: translateX(0);
                opacity: 1;
            }
        }

        .button-container:last-child {
            margin-bottom: 0;
        }

        /* Базовые стили для всех кнопок */
        button {
            font-size: 16px;
            font-weight: 600;
            padding: 16px 24px;
            border: none;
            border-radius: 12px;
            background: linear-gradient(135deg, var(--accent-color), var(--accent-hover));
            color: var(--button-text-color);
            cursor: pointer;
            transition: all 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            box-shadow: 0 4px 16px rgba(74, 222, 128, 0.3);
            position: relative;
            overflow: hidden;
            flex: 1;
        }

        button::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.3), transparent);
            transition: left 0.6s ease;
        }

        button:hover {
            transform: translateY(-3px) scale(1.02);
            box-shadow: 0 12px 28px rgba(74, 222, 128, 0.4);
        }

        button:hover::before {
            left: 100%;
        }

        button:active {
            transform: translateY(-1px) scale(0.98);
            transition: all 0.1s ease;
        }

        button.remove {
            background: linear-gradient(135deg, var(--error-color), #dc2626);
            color: #ffffff;
            width: 48px;
            height: 48px;
            padding: 0;
            flex: none;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 18px;
            font-weight: 700;
            box-shadow: 0 4px 16px rgba(239, 68, 68, 0.3);
            animation: rotateIn 0.5s ease-out;
        }

        @keyframes rotateIn {
            from {
                transform: rotate(-180deg) scale(0);
                opacity: 0;
            }
            to {
                transform: rotate(0deg) scale(1);
                opacity: 1;
            }
        }

        button.remove:hover {
            box-shadow: 0 8px 24px rgba(239, 68, 68, 0.4);
            transform: translateY(-3px) scale(1.1) rotate(90deg);
        }

        button.close_btn {
            border-radius: 12px;
            padding: 16px 20px;
        }

        /* Стили для языкового переключателя */
        .language-switcher {
            position: absolute;
            top: 16px;
            right: 16px;
            display: flex;
            gap: 6px;
            z-index: 10;
            transform: translateY(-10px);
            opacity: 0;
            animation: slideInFade 0.6s ease-out 1s forwards;
        }

        .language-switcher button {
            padding: 6px 10px !important;
            border: 1px solid var(--text-secondary) !important;
            background: transparent !important;
            background-image: none !important;
            background-color: transparent !important;
            color: var(--text-secondary) !important;
            border-radius: 6px !important;
            font-size: 11px !important;
            font-weight: 500 !important;
            width: auto !important;
            flex: none !important;
            box-shadow: none !important;
            transition: all 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) !important;
            min-width: 32px;
            transform: scale(0.9);
        }

        .language-switcher button:hover {
            transform: scale(1) translateY(-2px) !important;
            border-color: var(--accent-color) !important;
            color: var(--accent-color) !important;
            box-shadow: 0 4px 12px rgba(74, 222, 128, 0.2) !important;
        }

        .language-switcher button.active {
            background: var(--accent-color) !important;
            color: #000000 !important;
            border-color: var(--accent-color) !important;
            transform: scale(1) !important;
        }

        @keyframes slideInFade {
            from {
                opacity: 0;
                transform: translateY(30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 2px solid rgba(255, 255, 255, 0.3);
            border-radius: 50%;
            border-top-color: var(--accent-color);
            animation: spin 1s linear infinite;
            margin-right: 8px;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        /* Ripple effect */
        .ripple {
            position: absolute;
            border-radius: 50%;
            background: rgba(74, 222, 128, 0.3);
            transform: scale(0);
            animation: rippleEffect 0.6s linear;
            pointer-events: none;
        }

        @keyframes rippleEffect {
            to {
                transform: scale(4);
                opacity: 0;
            }
        }

        /* Success celebration */
        .success-celebration {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            pointer-events: none;
            z-index: 1000;
        }

        .confetti {
            position: absolute;
            width: 8px;
            height: 8px;
            background: var(--accent-color);
            animation: confettiFall 2s ease-out forwards;
        }

        @keyframes confettiFall {
            0% { transform: translateY(-50px) rotate(0deg); opacity: 1; }
            100% { transform: translateY(200px) rotate(720deg); opacity: 0; }
        }

        /* Loading overlay */
        .loading-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            opacity: 0;
            visibility: hidden;
            transition: all 0.3s ease;
        }

        .loading-overlay.active {
            opacity: 1;
            visibility: visible;
        }

        .loading-spinner {
            width: 60px;
            height: 60px;
            border: 4px solid rgba(255, 255, 255, 0.3);
            border-radius: 50%;
            border-top-color: var(--accent-color);
            animation: spin 1s linear infinite;
        }

        /* Enhanced responsive design */
        @media (max-width: 480px) {
            .main-container {
                padding: 20px 16px;
            }
            
            .form-card,
            .payment-methods {
                padding: 20px;
            }
            
            h2 {
                font-size: 24px;
            }

            .language-switcher {
                top: 12px;
                right: 12px;
                gap: 4px;
            }

            .language-switcher button {
                padding: 4px 8px !important;
                font-size: 10px !important;
                min-width: 28px;
            }
        }

        /* Desktop/Tablet styles for Telegram Web App */
        @media (min-width: 481px) {
            .main-container {
                max-width: 480px;
                padding: 32px 24px;
                gap: 32px;
            }
            
            .form-card,
            .payment-methods {
                padding: 32px;
            }
            
            h2 {
                font-size: 32px;
            }
            
            .header-icon {
                width: 80px;
                height: 80px;
                font-size: 32px;
                margin-bottom: 20px;
            }
            
            button {
                padding: 18px 28px;
                font-size: 17px;
            }
            
            input[type="number"],
            input[type="email"] {
                padding: 20px 24px;
                font-size: 17px;
            }
            
            .input-label {
                font-size: 17px;
                left: 24px;
            }

            .input-label.active {
                top: -16px;
                left: 16px;
                transform: translateY(0) scale(0.76);
                padding: 2px 8px;
            }

            input[type="number"]:focus + .input-label,
            input[type="email"]:focus + .input-label,
            input[type="number"]:not(:placeholder-shown) + .input-label,
            input[type="email"]:not(:placeholder-shown) + .input-label {
                top: -16px;
                left: 16px;
                transform: translateY(0) scale(0.76);
                padding: 2px 8px;
            }

            .input-validation {
                right: 20px;
                font-size: 18px;
            }

            .button-container {
                gap: 16px;
                margin-bottom: 16px;
            }
            
            button.remove {
                width: 52px;
                height: 52px;
                font-size: 20px;
            }

            .language-switcher {
                top: 20px;
                right: 20px;
                gap: 8px;
            }

            .language-switcher button {
                padding: 8px 12px !important;
                font-size: 12px !important;
                min-width: 36px;
            }

            .input-label {
                font-size: 17px;
                top: 18px;
            }

            .input-label.active {
                font-size: 13px;
            }

            .typing-placeholder {
                font-size: 17px;
                top: 18px;
            }

            input[type="number"]:focus + .input-label,
            input[type="email"]:focus + .input-label,
            input[type="number"]:not(:placeholder-shown) + .input-label,
            input[type="email"]:not(:placeholder-shown) + .input-label {
                font-size: 13px;
            }
        }

        /* Extra large screens */
        @media (min-width: 768px) {
            .main-container {
                max-width: 520px;
                padding: 40px 32px;
            }
            
            .form-card,
            .payment-methods {
                padding: 36px;
            }

            .language-switcher {
                top: 24px;
                right: 24px;
            }
        }

        /* Скрытие элементов */
        [style*="display: none"] {
            display: none !important;
        }
    </style>
</head>

<body class="" style="visibility: hidden;">

<div class="bg-particles" id="particles"></div>
<div class="loading-overlay" id="loadingOverlay">
    <div class="loading-spinner"></div>
</div>

<div class="language-switcher">
    <button data-lang="ru" class="active">RU</button>
    <button data-lang="en">EN</button>
</div>

<section class="main-container">
    <div class="header">
        <div class="header-icon" onclick="PaymentApp.iconClick()">💳</div>
        <h2 data-i18n="subscription_payment">Оплата подписки HQ VPN</h2>
    </div>

    <div class="form-card">
        <span id="form_amount" style="display: block;">
            <h4 data-i18n="payment_amount" style="text-align:left;">Сумма к оплате:</h4>
            <div class="input-wrapper">
                <input
                    type="number"
                    step="0.01"
                    min="1"
                    class="input"
                    value=""
                    id="text_amount"
                    placeholder=" "
                    inputmode="numeric"
                    pattern="\d*"
                    required
                />
            </div>
        </span>
        
        <span id="form_email" style="display: none;">
            <h4 data-i18n="text_email" style="text-align:left;">Email для чеков:</h4>
            <div class="input-wrapper">
                <input
                    type="email"
                    class="input"
                    value=""
                    id="text_email"
                    placeholder=" "
                    required
                />
            </div>
        </span>
    </div>

    <div class="payment-methods">
        <section id="main_section">
            <h4 data-i18n="select_payment_method" style="text-align:left;">Выберите способ оплаты:</h4>
        </section>
    </div>
</section>

<script type="application/javascript">
    let currentLang = 'ru';
    const translations = {
        en: {
            subscription_payment: "Subscription Payment",
            payment_amount: "Payment Amount:",
            select_payment_method: "Select Payment Method:",
            enter_amount: "Amount in RUB",
            text_email: "Email:",
            enter_amount_alert: "Please enter amount",
            invalid_email_alert: "Error: Enter valid Email"
        },
        ru: {
            subscription_payment: "Оплата подписки HQ VPN",
            payment_amount: "Введите сумму, на которую вы хотите пополнить ваш аккаунт, для возможности дальнейшего приобретения подписки:",
            select_payment_method: "Выберите способ оплаты:",
            enter_amount: "Сумма в рублях",
            text_email: "Email для чеков:",
            enter_amount_alert: "Введите сумму",
            invalid_email_alert: "Ошибка: Введите корректный Email"
        },
        fa: {
            subscription_payment: "پرداخت اشتراک",
            payment_amount: "مبلغ پرداختی:",
            select_payment_method: "روش پرداخت را انتخاب کنید:",
            enter_amount: "مبلغ پرداختی را وارد کنید",
            text_email: "Email:",
            enter_amount_alert: "مبلغ را وارد کنید",
            invalid_email_alert: "خطا: ایمیل صحیح وارد کنید"
        }
    };

    // Create animated background particles
    function createParticles() {
        const container = document.getElementById('particles');
        const particleCount = 25;
        
        for (let i = 0; i < particleCount; i++) {
            const particle = document.createElement('div');
            particle.className = 'particle';
            particle.style.left = Math.random() * 100 + '%';
            particle.style.top = Math.random() * 100 + '%';
            particle.style.animationDelay = Math.random() * 6 + 's';
            particle.style.animationDuration = (4 + Math.random() * 4) + 's';
            container.appendChild(particle);
        }
    }

    // Add ripple effect to buttons
    function addRippleEffect(element, event) {
        const rect = element.getBoundingClientRect();
        const ripple = document.createElement('span');
        const size = Math.max(rect.width, rect.height);
        const x = event.clientX - rect.left - size / 2;
        const y = event.clientY - rect.top - size / 2;
        
        ripple.className = 'ripple';
        ripple.style.width = ripple.style.height = size + 'px';
        ripple.style.left = x + 'px';
        ripple.style.top = y + 'px';
        
        element.appendChild(ripple);
        
        setTimeout(() => ripple.remove(), 600);
    }

    // Create confetti celebration
    function createConfetti() {
        const celebration = document.createElement('div');
        celebration.className = 'success-celebration';
        document.body.appendChild(celebration);
        
        for (let i = 0; i < 20; i++) {
            const confetti = document.createElement('div');
            confetti.className = 'confetti';
            confetti.style.left = (Math.random() * 100 - 50) + 'px';
            confetti.style.animationDelay = Math.random() * 0.5 + 's';
            confetti.style.background = `hsl(${Math.random() * 360}, 70%, 60%)`;
            celebration.appendChild(confetti);
        }
        
        setTimeout(() => celebration.remove(), 2000);
    }

    // Enhanced loading overlay
    function showLoading() {
        document.getElementById('loadingOverlay').classList.add('active');
    }

    function hideLoading() {
        document.getElementById('loadingOverlay').classList.remove('active');
    }

    const PaymentApp = {
        iconClick() {
            const icon = document.querySelector('.header-icon');
            icon.style.transform = 'scale(0.9) rotate(15deg)';
            setTimeout(() => {
                icon.style.transform = '';
            }, 200);
            ShmPayApp.hapticFeedback('light');
        },

        hapticFeedback(type) {
            if (Telegram.WebApp.HapticFeedback) {
                switch (type) {
                    case 'light':
                        Telegram.WebApp.HapticFeedback.impactOccurred('light');
                        break;
                    case 'success':
                        Telegram.WebApp.HapticFeedback.notificationOccurred('success');
                        break;
                    case 'error':
                        Telegram.WebApp.HapticFeedback.notificationOccurred('error');
                        break;
                }
            }
        }
    };

    const ShmPayApp = {
        initData        : Telegram.WebApp.initData || '',
        initDataUnsafe  : Telegram.WebApp.initDataUnsafe || {},
        MainButton      : Telegram.WebApp.MainButton,
        ackEmail        : false,
        scrollTimer     : null,
        inputMode       : false,

        init(options) {
            document.body.style.visibility = '';
            Telegram.WebApp.ready();
            
            ShmPayApp.setCloseButton();
            createParticles();

            const userLang = ShmPayApp.detectLanguage();
            ShmPayApp.changeLanguage(userLang);

            ShmPayApp.initInputHandlers();

            showLoading();

            let urlParams = new URLSearchParams(window.location.search);
            let user_id = urlParams.get('user_id');
            let amount = urlParams.get('amount');
            let email = urlParams.get('email');
            let ack_email = urlParams.get('ack_email');

            ShmPayApp.setDefaultAmount( amount );
            document.getElementById('text_email').value = email;
            if (ack_email) {
                ShmPayApp.ackEmail = true;
                document.getElementById('form_email').style.display = 'block';
            }

            let xhrURL = new URL('/shm/v1/telegram/webapp/auth', window.location.origin);
            xhrURL.searchParams.set('uid', user_id );
            xhrURL.searchParams.set('initData', Telegram.WebApp.initData);

            let xhr = new XMLHttpRequest();
            xhr.open('GET', xhrURL);
            xhr.send();
            xhr.onload = function() {
                if (xhr.status === 200) {
                    ShmPayApp.session_id = JSON.parse(xhr.response).session_id;
                    ShmPayApp.loadPaySystems();
                    hideLoading();
                    Telegram.WebApp.expand();
                } else {
                    hideLoading();
                    Telegram.WebApp.showAlert("Ошибка авторизации");
                    Telegram.WebApp.close();
                }
            };
        },

        initInputHandlers() {
            const amountInput = document.getElementById('text_amount');
            const emailInput = document.getElementById('text_email');

            ShmPayApp.createAdvancedInput(amountInput, {
                label: translations[currentLang].enter_amount,
                type: 'amount',
                validation: (value) => value && parseFloat(value) >= 1
            });

            ShmPayApp.createAdvancedInput(emailInput, {
                label: translations[currentLang].text_email,
                type: 'email',
                validation: (value) => {
                    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                    return emailPattern.test(value);
                }
            });

            // Enhanced input event handlers
            [amountInput, emailInput].forEach(input => {
                input.addEventListener('focus', () => {
                    ShmPayApp.setDoneButton();
                    input.parentElement.classList.add('focused');
                    ShmPayApp.hapticFeedback('light');
                });

                input.addEventListener('blur', () => {
                    input.parentElement.classList.remove('focused');
                });

                input.addEventListener('input', (e) => {
                    ShmPayApp.validateInput(e.target);
                    if (!ShmPayApp.inputMode) {
                        ShmPayApp.setDoneButton();
                    }
                });
            });

            document.addEventListener('focusout', (event) => {
                if (event.target.tagName === 'INPUT') {
                    setTimeout(() => {
                        if (!document.querySelector('input:focus')) {
                            ShmPayApp.setCloseButton();
                        }
                    }, 100);
                }
            });
        },

        createAdvancedInput(input, options) {
            const wrapper = input.parentElement;
            
            input.placeholder = ' ';
            
            const label = document.createElement('div');
            label.className = 'input-label';
            label.textContent = options.label;
            
            const validation = document.createElement('div');
            validation.className = 'input-validation';
            
            wrapper.appendChild(label);
            wrapper.appendChild(validation);
            
            input.dataset.inputOptions = JSON.stringify(options);
            
            input.addEventListener('focus', () => {
                label.classList.add('active');
            });
            
            input.addEventListener('blur', () => {
                if (!input.value.trim()) {
                    label.classList.remove('active');
                }
            });
            
            if (input.value) {
                label.classList.add('active');
                ShmPayApp.validateInput(input);
            }
        },

        validateInput(input) {
            const options = JSON.parse(input.dataset.inputOptions || '{}');
            const validation = input.parentElement.querySelector('.input-validation');
            
            if (!validation || !options.validation) return;
            
            const isValid = options.validation(input.value);
            
            validation.classList.remove('valid', 'invalid');
            
            if (input.value) {
                if (isValid) {
                    validation.innerHTML = '✓';
                    validation.classList.add('valid');
                    ShmPayApp.hapticFeedback('light');
                } else {
                    validation.innerHTML = '✗';
                    validation.classList.add('invalid');
                    ShmPayApp.hapticFeedback('error');
                }
            } else {
                validation.classList.remove('valid', 'invalid');
            }
        },

        loadPaySystems() {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '/shm/v1/user/pay/paysystems');
            xhr.setRequestHeader('session-id', ShmPayApp.session_id );
            xhr.send();
            xhr.onload = function() {
                if (xhr.status === 200) {
                    let data = JSON.parse(xhr.response).data;
                    ShmPayApp.setDefaultAmount( data[0].amount );

                    data.forEach((pay_system, index) => {
                        setTimeout(() => {
                            let btn_container = document.createElement('div');
                            btn_container.className = "button-container";
                            document.getElementById("main_section").appendChild(btn_container);

                            let btn_payment = document.createElement('button');
                            btn_payment.innerHTML = pay_system.name;
                            btn_payment.onclick = function(e){ 
                                addRippleEffect(btn_payment, e);
                                setTimeout(() => {
                                    ShmPayApp.makePayment(pay_system.shm_url, pay_system.recurring);
                                }, 200);
                            };
                            btn_container.appendChild(btn_payment);

                            if (pay_system.recurring) {
                                let btn_remove = document.createElement('button');
                                btn_remove.id = pay_system.paysystem;
                                btn_remove.className = "remove";
                                btn_remove.innerHTML = "×";
                                btn_remove.onclick = function(e){ 
                                    addRippleEffect(btn_remove, e);
                                    setTimeout(() => {
                                        ShmPayApp.removePayment(pay_system.pay_system);
                                    }, 200);
                                };
                                btn_container.appendChild(btn_remove);
                            }
                        }, index * 100);
                    });
                } else {
                    ShmPayApp.hapticFeedback('error');
                    Telegram.WebApp.showAlert("Ошибка");
                    Telegram.WebApp.close();
                }
            };

            // Enhanced language switcher
            document.querySelectorAll('.language-switcher button').forEach(button => {
                button.addEventListener('click', (event) => {
                    addRippleEffect(button, event);
                    ShmPayApp.hapticFeedback('light');
                    setTimeout(() => {
                        ShmPayApp.changeLanguage(event.target.dataset.lang);
                    }, 100);
                });
            });
            const userLang = ShmPayApp.detectLanguage();
            ShmPayApp.changeLanguage(userLang);
        },

        setDefaultAmount(amount) {
            let text_amount = document.getElementById('text_amount');
            text_amount.value ||= amount;
        },

        makePayment(shm_url, recurring) {
            var amount = document.getElementById('text_amount').value;
            if ( amount < 1 || !amount ) {
                ShmPayApp.hapticFeedback('error');
                Telegram.WebApp.showAlert(translations[currentLang].enter_amount_alert);
                return;
            };

            var email = document.getElementById('text_email').value;
            if (ShmPayApp.ackEmail) {
                var emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                if (!emailPattern.test(email)) {
                    ShmPayApp.hapticFeedback('error');
                    Telegram.WebApp.showAlert(translations[currentLang].invalid_email_alert);
                    return;
                }
            }

            if ( recurring == '1' ) {
                showLoading();
                document.getElementById('main_section').style.display = 'none';

                var xhr = new XMLHttpRequest();
                xhr.open('GET', shm_url + amount);
                xhr.responseType = 'json';

                xhr.onload = function() {
                    hideLoading();
                    if (xhr.status === 200) {
                        createConfetti();
                        ShmPayApp.hapticFeedback('success');
                        Telegram.WebApp.showAlert( "Платеж проведен успешно" );
                    } else {
                        var jsonResponse = xhr.response;
                        ShmPayApp.hapticFeedback('error');
                        Telegram.WebApp.showAlert( "Ошибка: " + ( jsonResponse.msg_ru || jsonResponse.msg ) );
                    }
                    Telegram.WebApp.close();
                }
                xhr.send();
            } else {
                ShmPayApp.hapticFeedback('light');
                Telegram.WebApp.openLink( shm_url + amount + '&email=' +email, { try_instant_view: false } );
                Telegram.WebApp.close();
            }
        },

        removePayment(id) {
            ShmPayApp.hapticFeedback('light');
            Telegram.WebApp.showConfirm('Отвязать сохраненный способ оплаты?', function(confirmed) {
                if (!confirmed) return;

                const element = document.getElementById(id);
                element.style.transform = 'scale(0) rotate(180deg)';
                element.style.opacity = '0';
                
                setTimeout(() => {
                    element.style.display = 'none';
                }, 300);

                let xhrURL = new URL('/shm/v1/user/autopayment', window.location.origin);
                xhrURL.searchParams.set('pay_system', id );
                var xhr = new XMLHttpRequest();
                xhr.open('DELETE', xhrURL);

                xhr.setRequestHeader('session-id', ShmPayApp.session_id );
                xhr.send();
                
                ShmPayApp.hapticFeedback('success');
            });
        },

        hapticFeedback(type) {
            PaymentApp.hapticFeedback(type);
        },

        expand() {
            Telegram.WebApp.expand();
        },
        close() {
            Telegram.WebApp.close();
        },
        setCloseButton() {
            Telegram.WebApp.MainButton.setParams({
                text      : 'Закрыть',
                is_visible: true
            }).onClick(ShmPayApp.close).offClick(ShmPayApp.hideKeyboard);
            ShmPayApp.inputMode = false;
        },
        setDoneButton() {
            Telegram.WebApp.MainButton.setParams({
                text      : 'Готово',
                is_visible: true
            }).onClick(ShmPayApp.hideKeyboard).offClick(ShmPayApp.close);
            ShmPayApp.inputMode = true;
        },
        hideKeyboard() {
            if (document.activeElement) {
                document.activeElement.blur();
            }
            setTimeout(() => {
                ShmPayApp.setCloseButton();
            }, 100);
        },
        setDefaultAmount(amount) {
            let text_amount = document.getElementById('text_amount');
            text_amount.value ||= amount;
        },
        changeLanguage(lang) {
            currentLang = lang;
            document.querySelectorAll('[data-i18n]').forEach(element => {
                const key = element.getAttribute('data-i18n');
                element.textContent = translations[lang][key];
            });

            ShmPayApp.updatePlaceholders();

            document.querySelectorAll('.language-switcher button').forEach(button => {
                button.classList.toggle('active', button.dataset.lang === lang);
            });
        },
        detectLanguage() {
            const lang = navigator.language || navigator.userLanguage;
            if (lang.startsWith('ru')) {
                return 'ru';
            } else if (lang.startsWith('fa')) {
                return 'fa';
            } else {
                return 'en';
            }
        },
        updatePlaceholders() {
            const amountInput = document.getElementById('text_amount');
            const emailInput = document.getElementById('text_email');
            
            const amountLabel = amountInput.parentElement.querySelector('.input-label');
            const emailLabel = emailInput.parentElement.querySelector('.input-label');
            
            if (amountLabel) {
                amountLabel.textContent = translations[currentLang].enter_amount;
            }
            
            if (emailLabel) {
                emailLabel.textContent = translations[currentLang].text_email;
            }
        },
    }
</script>
<script type="application/javascript">
    ShmPayApp.init();
</script>
</body>
</html>