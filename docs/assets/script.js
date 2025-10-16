// Global variables
let changelogData = null;
let loadTestData = null;
let currentFilter = 'all';
let currentTestType = 'all';

// Initialize the application
document.addEventListener('DOMContentLoaded', function() {
    initializeApp();
    initializeNavigation();
    initializeScrollAnimations();
    initializeScrollEffects();
});

async function initializeApp() {
    // Load data files
    await loadData();
    
    // Initialize page-specific functionality
    const currentPage = getCurrentPage();
    
    switch(currentPage) {
        case 'changelog':
            initializeChangelog();
            break;
        case 'load-tests':
            initializeLoadTests();
            break;
        case 'access-request':
            initializeAccessRequest();
            break;
        default:
            initializeHomePage();
    }
}

function getCurrentPage() {
    const path = window.location.pathname;
    if (path.includes('changelog')) return 'changelog';
    if (path.includes('load-tests')) return 'load-tests';
    if (path.includes('access-request')) return 'access-request';
    return 'home';
}

async function loadData() {
    try {
        // Load changelog data
        const changelogResponse = await fetch('data/changelog.json');
        changelogData = await changelogResponse.json();
        
        // Load load test data
        const loadTestResponse = await fetch('data/load-tests.json');
        loadTestData = await loadTestResponse.json();
    } catch (error) {
        console.error('Error loading data:', error);
    }
}

// Changelog functionality
function initializeChangelog() {
    if (!changelogData) return;
    
    renderChangelog();
    setupChangelogFilters();
}

function renderChangelog() {
    const timeline = document.querySelector('.changelog-timeline');
    if (!timeline) return;
    
    const filteredEntries = getFilteredChangelogEntries();
    
    timeline.innerHTML = filteredEntries.map(entry => `
        <div class="changelog-entry ${entry.type} ${entry.breaking ? 'breaking' : ''}">
            <div class="entry-header">
                <div class="entry-date">${formatDate(entry.date)}</div>
                <div class="entry-type">${getTypeIcon(entry.type)} ${entry.type.toUpperCase()}</div>
                ${entry.breaking ? '<div class="breaking-badge">BREAKING</div>' : ''}
            </div>
            <div class="entry-content">
                <h3>${entry.title}</h3>
                <p class="entry-description">${entry.description}</p>
                <div class="entry-changes">
                    <h4>Changes:</h4>
                    <ul>
                        ${entry.changes.map(change => `<li>${change}</li>`).join('')}
                    </ul>
                </div>
                ${entry.breakingChanges ? `
                    <div class="breaking-changes">
                        <h4>Breaking Changes:</h4>
                        <ul>
                            ${entry.breakingChanges.map(change => `<li>${change}</li>`).join('')}
                        </ul>
                    </div>
                ` : ''}
                ${entry.dockerImages ? `
                    <div class="docker-images">
                        <h4>Docker Images:</h4>
                        <div class="docker-list">
                            ${entry.dockerImages.map(img => `
                                <div class="docker-image">
                                    <span class="service">${img.service}</span>
                                    <span class="repository">${img.repository}</span>
                                    <span class="tag">${img.tag}</span>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                ` : ''}
            </div>
        </div>
    `).join('');
}

function getFilteredChangelogEntries() {
    if (!changelogData) return [];
    
    let entries = changelogData.changelog;
    
    if (currentFilter === 'helm') {
        entries = entries.filter(entry => entry.type === 'helm');
    } else if (currentFilter === 'docker') {
        entries = entries.filter(entry => entry.type === 'docker');
    } else if (currentFilter === 'breaking') {
        entries = entries.filter(entry => entry.breaking);
    }
    
    return entries.sort((a, b) => new Date(b.date) - new Date(a.date));
}

function setupChangelogFilters() {
    const filterButtons = document.querySelectorAll('.filter-btn');
    
    filterButtons.forEach(button => {
        button.addEventListener('click', function() {
            // Remove active class from all buttons
            filterButtons.forEach(btn => btn.classList.remove('active'));
            
            // Add active class to clicked button
            this.classList.add('active');
            
            // Update current filter
            currentFilter = this.dataset.filter;
            
            // Re-render changelog
            renderChangelog();
        });
    });
}

// Load Tests functionality
function initializeLoadTests() {
    if (!loadTestData) return;
    
    setupDateRangeSelector();
    setupTestTypeSelector();
    renderLoadTestMetrics();
    renderTestResultsTable();
    setupCharts();
    setupAnalysisTabs();
}

function setupDateRangeSelector() {
    const startDateInput = document.getElementById('startDate');
    const endDateInput = document.getElementById('endDate');
    const applyButton = document.getElementById('applyDateFilter');
    
    // Set default date range (last 30 days)
    const today = new Date();
    const thirtyDaysAgo = new Date(today.getTime() - (30 * 24 * 60 * 60 * 1000));
    
    startDateInput.value = formatDateForInput(thirtyDaysAgo);
    endDateInput.value = formatDateForInput(today);
    
    applyButton.addEventListener('click', function() {
        const startDate = new Date(startDateInput.value);
        const endDate = new Date(endDateInput.value);
        
        // Filter and re-render data
        filterLoadTestData(startDate, endDate);
    });
}

function setupTestTypeSelector() {
    const testTypeButtons = document.querySelectorAll('.test-type-btn');
    
    testTypeButtons.forEach(button => {
        button.addEventListener('click', function() {
            // Remove active class from all buttons
            testTypeButtons.forEach(btn => btn.classList.remove('active'));
            
            // Add active class to clicked button
            this.classList.add('active');
            
            // Update current test type
            currentTestType = this.dataset.type;
            
            // Re-render data
            renderLoadTestMetrics();
            renderTestResultsTable();
        });
    });
}

function renderLoadTestMetrics() {
    const filteredTests = getFilteredLoadTests();
    
    if (filteredTests.length === 0) return;
    
    // Calculate aggregated metrics
    const avgResponseTime = Math.round(filteredTests.reduce((sum, test) => sum + test.avgResponseTime, 0) / filteredTests.length);
    const maxConcurrentUsers = Math.max(...filteredTests.map(test => test.concurrentUsers));
    const avgThroughput = Math.round(filteredTests.reduce((sum, test) => sum + test.throughput, 0) / filteredTests.length);
    const avgErrorRate = (filteredTests.reduce((sum, test) => sum + test.errorRate, 0) / filteredTests.length).toFixed(1);
    
    // Update metric cards
    document.getElementById('avgResponseTime').textContent = avgResponseTime + 'ms';
    document.getElementById('concurrentUsers').textContent = maxConcurrentUsers;
    document.getElementById('throughput').textContent = avgThroughput.toLocaleString() + ' req/s';
    document.getElementById('errorRate').textContent = avgErrorRate + '%';
}

function renderTestResultsTable() {
    const tbody = document.getElementById('testResultsTableBody');
    if (!tbody) return;
    
    const filteredTests = getFilteredLoadTests();
    
    tbody.innerHTML = filteredTests.map(test => `
        <tr>
            <td>
                <div class="test-id">
                    <i class="fas fa-hashtag"></i>
                    <span>${test.id}</span>
                </div>
            </td>
            <td>
                <div class="test-datetime">
                    <div class="test-date">${formatDate(test.date)}</div>
                    <div class="test-time">${test.time}</div>
                </div>
            </td>
            <td>
                <span class="duration-badge">${test.duration}</span>
            </td>
            <td>
                <div class="users-info">
                    <i class="fas fa-users"></i>
                    <span>${test.concurrentUsers}</span>
                </div>
            </td>
            <td>
                <div class="response-time">
                    <span class="response-value">${test.avgResponseTime}ms</span>
                </div>
            </td>
            <td>
                <div class="response-time">
                    <span class="response-value">${test.p95ResponseTime}ms</span>
                </div>
            </td>
            <td>
                <div class="throughput">
                    <span class="throughput-value">${test.throughput.toLocaleString()}</span>
                    <span class="throughput-unit">req/s</span>
                </div>
            </td>
            <td>
                <div class="error-rate ${test.errorRate > 1 ? 'high' : test.errorRate > 0.5 ? 'medium' : 'low'}">
                    <span class="error-value">${test.errorRate}%</span>
                </div>
            </td>
            <td>
                <span class="status-badge ${test.status}">${test.status.toUpperCase()}</span>
            </td>
            <td>
                <button class="view-btn" onclick="viewTestDetails('${test.id}')" title="View Details">
                    <i class="fas fa-eye"></i>
                </button>
            </td>
        </tr>
    `).join('');
}

function getFilteredLoadTests() {
    if (!loadTestData) return [];
    
    let tests = loadTestData.loadTests;
    
    if (currentTestType !== 'all') {
        tests = tests.filter(test => test.type === currentTestType);
    }
    
    return tests.sort((a, b) => new Date(b.date + ' ' + b.time) - new Date(a.date + ' ' + a.time));
}

function setupCharts() {
    // Response Time Chart
    const responseTimeCtx = document.getElementById('responseTimeChart');
    if (responseTimeCtx) {
        new Chart(responseTimeCtx, {
            type: 'line',
            data: {
                labels: loadTestData.loadTests.map(test => formatDate(test.date)),
                datasets: [{
                    label: 'Response Time (ms)',
                    data: loadTestData.loadTests.map(test => test.avgResponseTime),
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });
    }
    
    // Throughput Chart
    const throughputCtx = document.getElementById('throughputChart');
    if (throughputCtx) {
        new Chart(throughputCtx, {
            type: 'bar',
            data: {
                labels: loadTestData.loadTests.map(test => formatDate(test.date)),
                datasets: [{
                    label: 'Throughput (req/s)',
                    data: loadTestData.loadTests.map(test => test.throughput),
                    backgroundColor: '#764ba2',
                    borderColor: '#667eea',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });
    }
}

function setupAnalysisTabs() {
    const tabButtons = document.querySelectorAll('.tab-btn');
    const tabPanels = document.querySelectorAll('.tab-panel');
    
    tabButtons.forEach(button => {
        button.addEventListener('click', function() {
            const targetTab = this.dataset.tab;
            
            // Remove active class from all buttons and panels
            tabButtons.forEach(btn => btn.classList.remove('active'));
            tabPanels.forEach(panel => panel.classList.remove('active'));
            
            // Add active class to clicked button and corresponding panel
            this.classList.add('active');
            document.getElementById(targetTab).classList.add('active');
        });
    });
}

// Access Request functionality
function initializeAccessRequest() {
    const form = document.getElementById('accessRequestForm');
    if (form) {
        form.addEventListener('submit', handleAccessRequest);
    }
}

function handleAccessRequest(event) {
    event.preventDefault();
    
    const formData = new FormData(event.target);
    const data = Object.fromEntries(formData.entries());
    
    // Get checkbox values
    const accessTypes = Array.from(document.querySelectorAll('input[name="accessTypes"]:checked'))
        .map(input => input.value);
    const agreements = Array.from(document.querySelectorAll('input[name="agreements"]:checked'))
        .map(input => input.value);
    
    data.accessTypes = accessTypes;
    data.agreements = agreements;
    
    // Show success message
    showNotification('Access request submitted successfully! We will get back to you within 24-48 hours.', 'success');
    
    // Reset form
    event.target.reset();
}

// Utility functions
function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });
}

// Copy to clipboard function
function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(function() {
        showNotification('Command copied to clipboard!', 'success');
    }, function(err) {
        console.error('Could not copy text: ', err);
        showNotification('Failed to copy command', 'error');
    });
}

// Show service details modal
function showServiceDetails(serviceName) {
    const serviceDetails = {
        'apollo': {
            title: 'Apollo API Service',
            description: 'Main Composio API service handling all tool integrations and agent requests',
            details: {
                'Port': '9900',
                'Type': 'NodePort',
                'Namespace': 'composio',
                'Service': 'composio-apollo',
                'Health Check': '/health',
                'Metrics': '/metrics'
            },
            commands: [
                'kubectl port-forward -n composio svc/composio-apollo 8080:9900',
                'kubectl logs -n composio deployment/composio-apollo',
                'kubectl describe svc composio-apollo -n composio'
            ]
        },
        'mcp': {
            title: 'MCP Portal Service',
            description: 'Management and Control Portal for monitoring and configuring Composio services',
            details: {
                'Port': '3000',
                'Type': 'ClusterIP',
                'Namespace': 'composio',
                'Service': 'composio-mcp',
                'Health Check': '/health',
                'Features': 'Dashboard, Monitoring, Configuration'
            },
            commands: [
                'kubectl port-forward -n composio svc/composio-mcp 8081:3000',
                'kubectl logs -n composio deployment/composio-mcp',
                'kubectl describe svc composio-mcp -n composio'
            ]
        },
        'thermos': {
            title: 'Thermos Workflow Engine',
            description: 'Workflow engine for orchestrating complex multi-step tool executions',
            details: {
                'Engine': 'Temporal',
                'Namespace': 'composio',
                'Service': 'composio-thermos',
                'Workflows': 'Active',
                'Scaling': 'Auto'
            },
            commands: [
                'kubectl logs -n composio deployment/composio-thermos',
                'kubectl describe deployment composio-thermos -n composio',
                'kubectl get workflows -n composio'
            ]
        },
        'mercury': {
            title: 'Mercury Serverless Service',
            description: 'Serverless function service for on-demand tool execution and scaling',
            details: {
                'Runtime': 'Knative',
                'Scaling': 'Auto',
                'Namespace': 'composio',
                'Service': 'composio-mercury',
                'Functions': 'On-demand'
            },
            commands: [
                'kubectl logs -n composio deployment/composio-mercury',
                'kubectl describe ksvc composio-mercury -n composio',
                'kubectl get pods -n composio -l app=mercury'
            ]
        },
        'temporal': {
            title: 'Temporal Workflow Orchestration',
            description: 'Workflow orchestration and state management for reliable task execution',
            details: {
                'UI Port': '8080',
                'Type': 'ClusterIP',
                'Namespace': 'composio',
                'Service': 'composio-temporal-web',
                'Version': '0.64.0'
            },
            commands: [
                'kubectl port-forward -n composio svc/composio-temporal-web 8082:8080',
                'kubectl logs -n composio deployment/composio-temporal-web',
                'kubectl describe svc composio-temporal-web -n composio'
            ]
        },
        'minio': {
            title: 'MinIO Object Storage',
            description: 'Object storage for files, documents, and persistent data management',
            details: {
                'Console Port': '9001',
                'API Port': '9000',
                'Namespace': 'composio',
                'Service': 'composio-minio',
                'Version': '17.11.3'
            },
            commands: [
                'kubectl port-forward -n composio svc/composio-minio 8083:9001',
                'kubectl logs -n composio deployment/composio-minio',
                'kubectl describe svc composio-minio -n composio'
            ]
        },
        'redis': {
            title: 'Redis Cache Service',
            description: 'In-memory caching layer for improved performance and session management',
            details: {
                'Port': '6379',
                'Type': 'ClusterIP',
                'Namespace': 'composio',
                'Service': 'composio-redis',
                'Version': '17.11.3'
            },
            commands: [
                'kubectl logs -n composio deployment/composio-redis',
                'kubectl describe svc composio-redis -n composio',
                'kubectl exec -it deployment/composio-redis -n composio -- redis-cli'
            ]
        }
    };
    
    const service = serviceDetails[serviceName];
    if (!service) return;
    
    // Create modal
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `
        <div class="modal-content">
            <div class="modal-header">
                <h3>${service.title}</h3>
                <button class="modal-close">&times;</button>
            </div>
            <div class="modal-body">
                <div class="service-details-content">
                    <p class="service-description">${service.description}</p>
                    
                    <div class="service-info-section">
                        <h4>Service Information</h4>
                        <div class="info-grid">
                            ${Object.entries(service.details).map(([key, value]) => `
                                <div class="info-item">
                                    <span class="info-label">${key}:</span>
                                    <span class="info-value">${value}</span>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                    
                    <div class="service-commands-section">
                        <h4>Useful Commands</h4>
                        <div class="commands-list">
                            ${service.commands.map(cmd => `
                                <div class="command-item">
                                    <code class="command-code">${cmd}</code>
                                    <button class="copy-command-btn" onclick="copyToClipboard('${cmd}')">
                                        <i class="fas fa-copy"></i>
                                    </button>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    `;
    
    document.body.appendChild(modal);
    
    // Close modal functionality
    modal.querySelector('.modal-close').addEventListener('click', () => {
        modal.remove();
    });
    
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.remove();
        }
    });
}

// Show quick fix modal
function showQuickFix(category) {
    const fixes = {
        'common': {
            title: 'Common Issues Quick Fix',
            content: `
                <div class="quick-fix-content">
                    <h4>Check these first:</h4>
                    <ol>
                        <li>Verify all pods are running: <code>kubectl get pods -n composio</code></li>
                        <li>Check resource limits: <code>kubectl describe nodes</code></li>
                        <li>Review logs: <code>kubectl logs -n composio &lt;pod-name&gt;</code></li>
                        <li>Verify database connectivity</li>
                    </ol>
                    <h4>Common Solutions:</h4>
                    <ul>
                        <li>Restart failed pods: <code>kubectl delete pod &lt;pod-name&gt; -n composio</code></li>
                        <li>Check resource quotas: <code>kubectl describe quota -n composio</code></li>
                        <li>Verify secrets: <code>kubectl get secrets -n composio</code></li>
                    </ul>
                </div>
            `
        },
        'gke': {
            title: 'GKE Specific Issues',
            content: `
                <div class="quick-fix-content">
                    <h4>GKE Autopilot Considerations:</h4>
                    <ol>
                        <li>Ensure resource requests are within Autopilot limits</li>
                        <li>Check Cloud SQL connectivity and firewall rules</li>
                        <li>Verify IAM permissions for container registry</li>
                        <li>Review load balancer configuration</li>
                    </ol>
                    <h4>GKE Commands:</h4>
                    <ul>
                        <li>Check cluster info: <code>gcloud container clusters describe &lt;cluster-name&gt;</code></li>
                        <li>Review firewall: <code>gcloud compute firewall-rules list</code></li>
                        <li>Check IAM: <code>gcloud projects get-iam-policy &lt;project-id&gt;</code></li>
                    </ul>
                </div>
            `
        },
        'monitoring': {
            title: 'Monitoring & Debugging',
            content: `
                <div class="quick-fix-content">
                    <h4>Monitoring Commands:</h4>
                    <ol>
                        <li>Pod status: <code>kubectl get pods -n composio -o wide</code></li>
                        <li>Resource usage: <code>kubectl top pods -n composio</code></li>
                        <li>Service endpoints: <code>kubectl get endpoints -n composio</code></li>
                        <li>Network policies: <code>kubectl get networkpolicies -n composio</code></li>
                    </ol>
                    <h4>Log Analysis:</h4>
                    <ul>
                        <li>Follow logs: <code>kubectl logs -f &lt;pod-name&gt; -n composio</code></li>
                        <li>Previous logs: <code>kubectl logs --previous &lt;pod-name&gt; -n composio</code></li>
                        <li>All containers: <code>kubectl logs &lt;pod-name&gt; -c &lt;container-name&gt; -n composio</code></li>
                    </ul>
                </div>
            `
        }
    };
    
    const fix = fixes[category];
    if (!fix) return;
    
    // Create modal
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `
        <div class="modal-content">
            <div class="modal-header">
                <h3>${fix.title}</h3>
                <button class="modal-close">&times;</button>
            </div>
            <div class="modal-body">
                ${fix.content}
            </div>
        </div>
    `;
    
    document.body.appendChild(modal);
    
    // Close modal functionality
    modal.querySelector('.modal-close').addEventListener('click', () => {
        modal.remove();
    });
    
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.remove();
        }
    });
}

function formatDateForInput(date) {
    return date.toISOString().split('T')[0];
}

function getTypeIcon(type) {
    const icons = {
        'helm': 'fas fa-cube',
        'docker': 'fab fa-docker',
        'breaking': 'fas fa-exclamation-triangle'
    };
    return `<i class="${icons[type] || 'fas fa-circle'}"></i>`;
}

function showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification ${type}`;
    notification.innerHTML = `
        <div class="notification-content">
            <i class="fas fa-${type === 'success' ? 'check-circle' : 'info-circle'}"></i>
            <span>${message}</span>
        </div>
    `;
    
    // Add to page
    document.body.appendChild(notification);
    
    // Remove after 5 seconds
    setTimeout(() => {
        notification.remove();
    }, 5000);
}

function viewTestDetails(testId) {
    const test = loadTestData.loadTests.find(t => t.id === testId);
    if (!test) return;
    
    // Create modal or detailed view
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `
        <div class="modal-content">
            <div class="modal-header">
                <h3>Test Details: ${test.id}</h3>
                <button class="modal-close">&times;</button>
            </div>
            <div class="modal-body">
                <div class="test-details">
                    <div class="detail-row">
                        <span class="detail-label">Date:</span>
                        <span class="detail-value">${formatDate(test.date)} ${test.time}</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Type:</span>
                        <span class="detail-value">${test.type}</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Duration:</span>
                        <span class="detail-value">${test.duration}</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Concurrent Users:</span>
                        <span class="detail-value">${test.concurrentUsers}</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Average Response Time:</span>
                        <span class="detail-value">${test.avgResponseTime}ms</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">P95 Response Time:</span>
                        <span class="detail-value">${test.p95ResponseTime}ms</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">P99 Response Time:</span>
                        <span class="detail-value">${test.p99ResponseTime}ms</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Max Response Time:</span>
                        <span class="detail-value">${test.maxResponseTime}ms</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Throughput:</span>
                        <span class="detail-value">${test.throughput.toLocaleString()} req/s</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Error Rate:</span>
                        <span class="detail-value">${test.errorRate}%</span>
                    </div>
                    <div class="detail-row">
                        <span class="detail-label">Status:</span>
                        <span class="detail-value status-badge ${test.status}">${test.status.toUpperCase()}</span>
                    </div>
                </div>
                <div class="test-description">
                    <h4>Description:</h4>
                    <p>${test.description}</p>
                </div>
            </div>
        </div>
    `;
    
    document.body.appendChild(modal);
    
    // Close modal functionality
    modal.querySelector('.modal-close').addEventListener('click', () => {
        modal.remove();
    });
    
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.remove();
        }
    });
}

function filterLoadTestData(startDate, endDate) {
    // This would filter the load test data based on date range
    // For now, just re-render the existing data
    renderLoadTestMetrics();
    renderTestResultsTable();
}

// Navigation functionality
function initializeNavigation() {
    const mobileToggle = document.querySelector('.mobile-nav-toggle');
    const mobileMenu = document.querySelector('.mobile-nav-menu');
    const navLinks = document.querySelectorAll('.nav-link');
    
    if (mobileToggle && mobileMenu) {
        mobileToggle.addEventListener('click', function() {
            mobileMenu.classList.toggle('active');
            const icon = mobileToggle.querySelector('i');
            icon.classList.toggle('fa-bars');
            icon.classList.toggle('fa-times');
        });
        
        // Close mobile menu when clicking on a link
        navLinks.forEach(link => {
            link.addEventListener('click', function() {
                mobileMenu.classList.remove('active');
                const icon = mobileToggle.querySelector('i');
                icon.classList.add('fa-bars');
                icon.classList.remove('fa-times');
            });
        });
        
        // Close mobile menu when clicking outside
        document.addEventListener('click', function(e) {
            if (!mobileToggle.contains(e.target) && !mobileMenu.contains(e.target)) {
                mobileMenu.classList.remove('active');
                const icon = mobileToggle.querySelector('i');
                icon.classList.add('fa-bars');
                icon.classList.remove('fa-times');
            }
        });
    }
    
    // Set active nav link based on current page
    setActiveNavLink();
}

function setActiveNavLink() {
    const currentPath = window.location.pathname;
    const navLinks = document.querySelectorAll('.nav-link');
    
    navLinks.forEach(link => {
        link.classList.remove('active');
        
        if (currentPath === '/' || currentPath === '/index.html') {
            if (link.getAttribute('href') === '#quickstart') {
                link.classList.add('active');
            }
        } else if (currentPath.includes(link.getAttribute('href'))) {
            link.classList.add('active');
        }
    });
}

// Scroll animations
function initializeScrollAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };
    
    const observer = new IntersectionObserver(function(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animated');
            }
        });
    }, observerOptions);
    
    // Observe all elements with animate-on-scroll class
    document.querySelectorAll('.animate-on-scroll').forEach(el => {
        observer.observe(el);
    });
}

// Scroll effects
function initializeScrollEffects() {
    const navbar = document.querySelector('.navbar');
    let lastScrollTop = 0;
    
    window.addEventListener('scroll', function() {
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        
        // Add scrolled class to navbar
        if (scrollTop > 50) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }
        
        // Update last scroll position
        lastScrollTop = scrollTop;
    });
    
    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                const offsetTop = target.offsetTop - 80; // Account for fixed navbar
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        });
    });
}
