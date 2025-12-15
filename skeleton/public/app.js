// Fetch environment and update badge + flow diagram
fetch('/env')
  .then(res => res.json())
  .then(data => {
    const env = data.environment?.toLowerCase();
    
    // Update badge
    const badge = document.getElementById('envBadge');
    if (badge && env) {
      badge.textContent = env.toUpperCase();
      badge.className = 'env-badge env-' + env;
    }
    
    // Highlight current step in flow diagram
    if (env) {
      document.querySelectorAll('.step[data-env]').forEach(step => {
        step.classList.remove('final', 'completed');
        const stepEnv = step.getAttribute('data-env');
        
        // Mark current environment as final (highlighted)
        if (stepEnv === env) {
          step.classList.add('final');
        }
        // Mark previous environments as completed
        else if (
          (env === 'staging' && stepEnv === 'dev') ||
          (env === 'prod' && (stepEnv === 'dev' || stepEnv === 'staging'))
        ) {
          step.classList.add('completed');
        }
      });
    }
  })
  .catch(() => {});

// Fetch health status
fetch('/health')
  .then(res => res.json())
  .then(data => {
    const dot = document.getElementById('statusDot');
    if (dot && data.status === 'UP') {
      dot.classList.add('online');
    }
  })
  .catch(() => {});
