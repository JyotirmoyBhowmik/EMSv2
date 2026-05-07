import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

/*
  EMS RBAC UI Enforcement:
  Hide Daily Monitoring for EMS_Monitor / Monitor users.
  Admin users can still see Daily Monitoring.
*/
(function enforceEmsMonitorRestrictions() {
    function normalize(value) {
        return String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();
    }

    function getStorageText() {
        try {
            var keys = [
                'user',
                'emsUser',
                'currentUser',
                'authUser',
                'role',
                'groups',
                'emsRole',
                'emsGroups'
            ];

            var values = [];

            keys.forEach(function (key) {
                var localValue = localStorage.getItem(key);
                var sessionValue = sessionStorage.getItem(key);

                if (localValue) {
                    values.push(localValue);
                }

                if (sessionValue) {
                    values.push(sessionValue);
                }
            });

            return normalize(values.join(' '));
        } catch (e) {
            return '';
        }
    }

    function pageHasExactText(textValue) {
        var wanted = normalize(textValue);
        var elements = Array.prototype.slice.call(document.querySelectorAll('span, div, label, small, strong, button'));

        return elements.some(function (element) {
            return normalize(element.textContent) === wanted;
        });
    }

    function isMonitorOnlyUser() {
        var storageText = getStorageText();
        var monitorRegex = /(^|[^a-z0-9_])monitor([^a-z0-9_]|$)/i;
        var adminRegex = /(^|[^a-z0-9_])admin([^a-z0-9_]|$)/i;

        var isMonitor =
            storageText.indexOf('ems_monitor') !== -1 ||
            storageText.indexOf('ems monitor') !== -1 ||
            monitorRegex.test(storageText) ||
            pageHasExactText('Monitor');

        var isAdmin =
            storageText.indexOf('ems_admin') !== -1 ||
            storageText.indexOf('ems admin') !== -1 ||
            adminRegex.test(storageText) ||
            pageHasExactText('Admin');

        return isMonitor && !isAdmin;
    }

    function hideDailyMonitoringMenu() {
        var elements = Array.prototype.slice.call(document.querySelectorAll('a, button, li, div, span'));

        elements.forEach(function (element) {
            var text = normalize(element.textContent);

            if (text === 'daily monitoring') {
                var container =
                    element.closest('.nav-item') ||
                    element.closest('a') ||
                    element.closest('button') ||
                    element.closest('li') ||
                    element;

                if (container) {
                    container.style.setProperty('display', 'none', 'important');
                    container.setAttribute('data-ems-monitor-hidden', 'daily-monitoring');
                }
            }
        });
    }

    function showDailyMonitoringMenu() {
        var hiddenItems = document.querySelectorAll('[data-ems-monitor-hidden="daily-monitoring"]');

        hiddenItems.forEach(function (element) {
            element.style.removeProperty('display');
            element.removeAttribute('data-ems-monitor-hidden');
        });
    }

    function blockDailyUrl() {
        try {
            var url = new URL(window.location.href);
            var view = normalize(url.searchParams.get('view'));

            if (view === 'daily') {
                window.history.replaceState({}, '', '/dashboard');
                window.dispatchEvent(new PopStateEvent('popstate'));
            }
        } catch (e) {
        }
    }

    function applyPolicy() {
        var monitorOnly = isMonitorOnlyUser();

        document.body.classList.toggle('ems-monitor-only', monitorOnly);

        if (monitorOnly) {
            hideDailyMonitoringMenu();
            blockDailyUrl();
        } else {
            showDailyMonitoringMenu();
        }
    }

    function startPolicy() {
        applyPolicy();

        var observer = new MutationObserver(function () {
            applyPolicy();
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true
        });

        setInterval(applyPolicy, 500);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startPolicy);
    } else {
        startPolicy();
    }
})();

var root = ReactDOM.createRoot(document.getElementById('root'));

root.render(
    React.createElement(
        React.StrictMode,
        null,
        React.createElement(App, null)
    )
);

// EMS_PATCH_COMPLIANCE_REPORT_COLLECTION_FAILED_CARD_V7_BEGIN
// Compliance Report UI enhancement: add COLLECTION FAILED card without touching ComplianceReport JSX.
(function () {
    const normalizeText = (value) => String(value || '').replace(/\s+/g, ' ').trim().toUpperCase();
    const toNumber = (value) => {
        const match = String(value || '').match(/\d+/);
        return match ? parseInt(match[0], 10) : 0;
    };

    const findExactTextNode = (title) => {
        const expected = normalizeText(title);
        const nodes = Array.from(document.querySelectorAll('div, span, p, h1, h2, h3, h4, h5, h6'));
        return nodes.find((el) => normalizeText(el.textContent) === expected) || null;
    };

    const findCard = (title) => {
        const titleNode = findExactTextNode(title);
        if (!titleNode) return null;
        return titleNode.closest('.summary-card, .stat-card, .metric-card, .card') || titleNode.parentElement?.parentElement || titleNode.parentElement || null;
    };

    const cardValue = (card) => {
        if (!card) return 0;
        const nodes = Array.from(card.querySelectorAll('*'));
        const valueNode = nodes.find((el) => /^\s*\d+\s*$/.test(String(el.textContent || ''))) ||
            nodes.find((el) => /value|count|number/i.test(String(el.className || '')) && /\d+/.test(String(el.textContent || '')));
        return toNumber(valueNode ? valueNode.textContent : card.textContent);
    };

    const apply = () => {
        const pageTitle = findExactTextNode('COMPLIANCE REPORT');
        const totalCard = findCard('TOTAL HOSTS');
        const compliantCard = findCard('COMPLIANT');
        const partialCard = findCard('PARTIAL COMPLIANT');
        if (!pageTitle || !totalCard || !compliantCard || !partialCard) return;

        const failedCount = Math.max(cardValue(totalCard) - cardValue(compliantCard) - cardValue(partialCard), 0);
        const container = partialCard.parentElement;
        if (!container) return;

        let failedCard = container.querySelector('[data-ems-collection-failed-card-v7="true"]');
        if (!failedCard) {
            failedCard = partialCard.cloneNode(true);
            failedCard.setAttribute('data-ems-collection-failed-card-v7', 'true');
            container.appendChild(failedCard);
        }

        failedCard.style.background = '#dc3545';
        failedCard.style.backgroundColor = '#dc3545';
        failedCard.style.color = '#ffffff';

        const nodes = Array.from(failedCard.querySelectorAll('*'));
        const titleNode = nodes.find((el) => ['PARTIAL COMPLIANT', 'COLLECTION FAILED'].includes(normalizeText(el.textContent)));
        if (titleNode) titleNode.textContent = 'COLLECTION FAILED';

        const valueNode = nodes.find((el) => /^\s*\d+\s*$/.test(String(el.textContent || ''))) ||
            nodes.find((el) => /value|count|number/i.test(String(el.className || '')));
        if (valueNode) valueNode.textContent = String(failedCount);
    };

    window.addEventListener('load', apply);
    window.addEventListener('popstate', () => setTimeout(apply, 100));
    window.addEventListener('hashchange', () => setTimeout(apply, 100));
    setInterval(apply, 1500);
})();
// EMS_PATCH_COMPLIANCE_REPORT_COLLECTION_FAILED_CARD_V7_END
