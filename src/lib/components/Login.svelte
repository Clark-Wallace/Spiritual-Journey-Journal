<script lang="ts">
  import { authStore } from '../stores/auth';
  
  let isSignUp = false;
  let email = '';
  let password = '';
  let name = '';
  let error = '';
  let loading = false;
  
  async function handleSubmit() {
    error = '';
    loading = true;
    
    if (!email || !password) {
      error = 'Please fill in all fields';
      loading = false;
      return;
    }
    
    if (!email.includes('@')) {
      error = 'Please enter a valid email';
      loading = false;
      return;
    }
    
    if (password.length < 6) {
      error = 'Password must be at least 6 characters';
      loading = false;
      return;
    }
    
    if (isSignUp && !name) {
      error = 'Please enter your name';
      loading = false;
      return;
    }
    
    try {
      if (isSignUp) {
        await authStore.signUp(email, password, name);
        // Show success message for sign up
        error = '';
      } else {
        await authStore.signIn(email, password);
      }
    } catch (err: any) {
      console.error('Auth error:', err);
      // Better error messages
      if (err.message?.includes('Invalid login')) {
        error = 'Invalid email or password';
      } else if (err.message?.includes('Email not confirmed')) {
        error = 'Please check your email to confirm your account';
      } else if (err.message?.includes('User already registered')) {
        error = 'This email is already registered. Try signing in instead.';
      } else {
        error = err.message || 'An error occurred';
      }
    } finally {
      loading = false;
    }
  }
</script>

<div class="login-container">
  <div class="login-card">
    <h1>🕊️ Welcome</h1>
    <p class="subtitle">Your spiritual journey awaits</p>
    
    <form on:submit|preventDefault={handleSubmit}>
      {#if isSignUp}
        <div class="form-group">
          <input
            type="text"
            placeholder="Your name"
            bind:value={name}
            class="input"
            disabled={loading}
          />
        </div>
      {/if}
      
      <div class="form-group">
        <input
          type="email"
          placeholder="Email"
          bind:value={email}
          class="input"
          required
          disabled={loading}
        />
      </div>
      
      <div class="form-group">
        <input
          type="password"
          placeholder="Password (min 6 characters)"
          bind:value={password}
          class="input"
          required
          disabled={loading}
        />
      </div>
      
      {#if error}
        <p class="error">{error}</p>
      {/if}
      
      <button type="submit" class="submit-btn" disabled={loading}>
        {#if loading}
          Loading...
        {:else}
          {isSignUp ? 'Create Account' : 'Sign In'}
        {/if}
      </button>
    </form>
    
    <div class="toggle">
      <p>
        {isSignUp ? 'Already have an account?' : "Don't have an account?"}
        <button 
          class="link-btn"
          on:click={() => {
            isSignUp = !isSignUp;
            error = '';
          }}
          disabled={loading}
        >
          {isSignUp ? 'Sign In' : 'Sign Up'}
        </button>
      </p>
    </div>
    
    <div class="info">
      <p class="info-text">
        ✨ Your data is securely stored in the cloud<br>
        🔒 Access your journal from any device<br>
        📱 Works on phones, tablets, and computers
      </p>
    </div>
  </div>
</div>

<style>
  .login-container {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    padding: 1rem;
  }
  
  .login-card {
    background: white;
    border-radius: 12px;
    padding: 2rem;
    width: 100%;
    max-width: 400px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.1);
  }
  
  h1 {
    margin: 0 0 0.5rem 0;
    text-align: center;
    color: #333;
    font-size: 2rem;
  }
  
  .subtitle {
    text-align: center;
    color: #666;
    margin: 0 0 2rem 0;
  }
  
  .form-group {
    margin-bottom: 1rem;
  }
  
  .input {
    width: 100%;
    padding: 0.75rem;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    font-size: 1rem;
    transition: border-color 0.2s;
  }
  
  .input:focus {
    outline: none;
    border-color: #667eea;
  }
  
  .input:disabled {
    background: #f5f5f5;
    cursor: not-allowed;
  }
  
  .error {
    color: #e74c3c;
    text-align: center;
    margin: 0.5rem 0;
    font-size: 0.875rem;
  }
  
  .submit-btn {
    width: 100%;
    padding: 0.75rem;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 1rem;
    font-weight: 600;
    cursor: pointer;
    transition: transform 0.2s;
  }
  
  .submit-btn:hover:not(:disabled) {
    transform: translateY(-2px);
  }
  
  .submit-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  
  .toggle {
    text-align: center;
    margin-top: 1.5rem;
    color: #666;
  }
  
  .link-btn {
    background: none;
    border: none;
    color: #667eea;
    cursor: pointer;
    font-weight: 600;
    text-decoration: underline;
  }
  
  .link-btn:disabled {
    cursor: not-allowed;
    opacity: 0.6;
  }
  
  .info {
    margin-top: 2rem;
    padding-top: 1.5rem;
    border-top: 1px solid #f0f0f0;
  }
  
  .info-text {
    text-align: center;
    color: #999;
    font-size: 0.875rem;
    line-height: 1.5;
  }
</style>