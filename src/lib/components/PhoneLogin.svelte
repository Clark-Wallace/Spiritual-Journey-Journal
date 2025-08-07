<script lang="ts">
  import { authStore } from '../stores/auth';
  import { supabase } from '../supabase';
  
  let step: 'phone' | 'verify' | 'profile' = 'phone';
  let phone = '';
  let countryCode = '+1'; // Default to US
  let verificationCode = '';
  let name = '';
  let error = '';
  let loading = false;
  let resendTimer = 0;
  
  // Format phone number as user types
  function formatPhoneNumber(value: string) {
    const cleaned = value.replace(/\D/g, '');
    const match = cleaned.match(/^(\d{3})(\d{3})(\d{4})$/);
    if (match) {
      return `(${match[1]}) ${match[2]}-${match[3]}`;
    }
    return value;
  }
  
  // Handle phone input
  function handlePhoneInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const formatted = formatPhoneNumber(input.value);
    phone = formatted;
  }
  
  // Start resend timer
  function startResendTimer() {
    resendTimer = 60;
    const interval = setInterval(() => {
      resendTimer--;
      if (resendTimer <= 0) {
        clearInterval(interval);
      }
    }, 1000);
  }
  
  // Send verification code
  async function sendVerificationCode() {
    error = '';
    loading = true;
    
    // Clean phone number
    const cleanPhone = phone.replace(/\D/g, '');
    
    if (cleanPhone.length !== 10) {
      error = 'Please enter a valid 10-digit phone number';
      loading = false;
      return;
    }
    
    const fullPhone = `${countryCode}${cleanPhone}`;
    
    try {
      const { error: signUpError } = await supabase.auth.signInWithOtp({
        phone: fullPhone,
      });
      
      if (signUpError) throw signUpError;
      
      step = 'verify';
      startResendTimer();
    } catch (err: any) {
      console.error('Phone auth error:', err);
      error = err.message || 'Failed to send verification code';
    } finally {
      loading = false;
    }
  }
  
  // Verify code
  async function verifyCode() {
    error = '';
    loading = true;
    
    const cleanPhone = phone.replace(/\D/g, '');
    const fullPhone = `${countryCode}${cleanPhone}`;
    
    if (verificationCode.length !== 6) {
      error = 'Please enter the 6-digit code';
      loading = false;
      return;
    }
    
    try {
      const { data, error: verifyError } = await supabase.auth.verifyOtp({
        phone: fullPhone,
        token: verificationCode,
        type: 'sms'
      });
      
      if (verifyError) throw verifyError;
      
      // Check if user profile exists
      const { data: profile } = await supabase
        .from('user_profiles')
        .select('name')
        .eq('id', data.user?.id)
        .single();
      
      if (profile?.name) {
        // Existing user, sign them in
        window.location.reload();
      } else {
        // New user, get their name
        step = 'profile';
      }
    } catch (err: any) {
      console.error('Verification error:', err);
      error = err.message || 'Invalid verification code';
    } finally {
      loading = false;
    }
  }
  
  // Save profile
  async function saveProfile() {
    error = '';
    loading = true;
    
    if (!name.trim()) {
      error = 'Please enter your name';
      loading = false;
      return;
    }
    
    try {
      const user = (await supabase.auth.getUser()).data.user;
      if (!user) throw new Error('No user found');
      
      const { error: profileError } = await supabase
        .from('user_profiles')
        .upsert({
          id: user.id,
          name: name.trim(),
          phone_verified: true,
          verified_at: new Date().toISOString()
        });
      
      if (profileError) throw profileError;
      
      // Reload to show main app
      window.location.reload();
    } catch (err: any) {
      console.error('Profile error:', err);
      error = err.message || 'Failed to save profile';
    } finally {
      loading = false;
    }
  }
  
  // Resend code
  async function resendCode() {
    if (resendTimer > 0) return;
    await sendVerificationCode();
  }
</script>

<div class="login-container">
  <!-- Light rays for divine atmosphere -->
  <div class="light-rays">
    <div class="light-ray"></div>
    <div class="light-ray"></div>
    <div class="light-ray"></div>
  </div>
  
  <div class="login-card">
    <div class="header">
      <h1>🕊️ Spiritual Journey</h1>
      <p class="subtitle">A sacred space for fellowship</p>
    </div>
    
    {#if step === 'phone'}
      <form on:submit|preventDefault={sendVerificationCode}>
        <div class="step-indicator">
          <div class="step active">1</div>
          <div class="step">2</div>
          <div class="step">3</div>
        </div>
        
        <h2>Enter Your Phone Number</h2>
        <p class="info">We'll send you a verification code to ensure authentic fellowship</p>
        
        <div class="phone-input-group">
          <select bind:value={countryCode} class="country-select" disabled={loading}>
            <option value="+1">🇺🇸 +1</option>
            <option value="+44">🇬🇧 +44</option>
            <option value="+61">🇦🇺 +61</option>
            <option value="+91">🇮🇳 +91</option>
            <option value="+234">🇳🇬 +234</option>
            <option value="+27">🇿🇦 +27</option>
            <option value="+63">🇵🇭 +63</option>
          </select>
          
          <input
            type="tel"
            placeholder="(555) 123-4567"
            bind:value={phone}
            on:input={handlePhoneInput}
            class="phone-input"
            disabled={loading}
            maxlength="14"
          />
        </div>
        
        {#if error}
          <p class="error">❌ {error}</p>
        {/if}
        
        <button type="submit" class="submit-btn" disabled={loading}>
          {loading ? 'Sending...' : 'Send Verification Code'}
        </button>
        
        <div class="privacy-note">
          🔒 Your phone number is kept private and never shared with other users
        </div>
      </form>
      
    {:else if step === 'verify'}
      <form on:submit|preventDefault={verifyCode}>
        <div class="step-indicator">
          <div class="step completed">✓</div>
          <div class="step active">2</div>
          <div class="step">3</div>
        </div>
        
        <h2>Enter Verification Code</h2>
        <p class="info">We sent a 6-digit code to {countryCode} {phone}</p>
        
        <div class="code-input-wrapper">
          <input
            type="text"
            placeholder="000000"
            bind:value={verificationCode}
            class="code-input"
            maxlength="6"
            autocomplete="one-time-code"
            disabled={loading}
          />
        </div>
        
        {#if error}
          <p class="error">❌ {error}</p>
        {/if}
        
        <button type="submit" class="submit-btn" disabled={loading}>
          {loading ? 'Verifying...' : 'Verify Code'}
        </button>
        
        <div class="resend-section">
          {#if resendTimer > 0}
            <p class="resend-timer">Resend code in {resendTimer}s</p>
          {:else}
            <button type="button" class="link-btn" on:click={resendCode} disabled={loading}>
              Resend Code
            </button>
          {/if}
        </div>
        
        <button type="button" class="back-btn" on:click={() => step = 'phone'} disabled={loading}>
          ← Change Phone Number
        </button>
      </form>
      
    {:else if step === 'profile'}
      <form on:submit|preventDefault={saveProfile}>
        <div class="step-indicator">
          <div class="step completed">✓</div>
          <div class="step completed">✓</div>
          <div class="step active">3</div>
        </div>
        
        <h2>Welcome to the Fellowship!</h2>
        <p class="info">What should we call you?</p>
        
        <input
          type="text"
          placeholder="Your name"
          bind:value={name}
          class="input"
          disabled={loading}
          maxlength="50"
        />
        
        {#if error}
          <p class="error">❌ {error}</p>
        {/if}
        
        <button type="submit" class="submit-btn" disabled={loading}>
          {loading ? 'Creating Account...' : 'Begin Your Journey'}
        </button>
        
        <div class="verse-welcome">
          "Therefore encourage one another and build each other up" 
          <span class="verse-ref">- 1 Thessalonians 5:11</span>
        </div>
      </form>
    {/if}
  </div>
</div>

<style>
  .login-container {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(180deg, var(--bg-dark) 0%, var(--bg-dark-secondary) 100%);
    padding: 1rem;
    position: relative;
    overflow: hidden;
  }
  
  /* Light rays animation */
  .light-rays {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    overflow: hidden;
    pointer-events: none;
  }
  
  .light-ray {
    position: absolute;
    width: 2px;
    height: 300%;
    background: linear-gradient(to bottom, 
      transparent, 
      rgba(255, 215, 0, 0.05), 
      transparent);
    top: -100%;
    animation: rayMove 20s linear infinite;
  }
  
  .light-ray:nth-child(1) {
    left: 10%;
    animation-delay: 0s;
  }
  
  .light-ray:nth-child(2) {
    left: 50%;
    animation-delay: 7s;
  }
  
  .light-ray:nth-child(3) {
    left: 90%;
    animation-delay: 14s;
  }
  
  @keyframes rayMove {
    0% { transform: translateY(-100%) rotate(15deg); }
    100% { transform: translateY(100%) rotate(15deg); }
  }
  
  .login-card {
    background: linear-gradient(135deg, rgba(255, 255, 255, 0.95), rgba(255, 248, 220, 0.95));
    backdrop-filter: blur(10px);
    border: 2px solid var(--border-gold);
    border-radius: 16px;
    padding: 2.5rem;
    width: 100%;
    max-width: 420px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3),
                0 0 40px rgba(255, 215, 0, 0.1);
    position: relative;
    z-index: 1;
  }
  
  .header {
    text-align: center;
    margin-bottom: 2rem;
  }
  
  h1 {
    margin: 0;
    color: var(--primary-gold);
    font-size: 2.2rem;
    font-family: var(--font-primary);
    text-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  .subtitle {
    margin: 0.5rem 0 0;
    color: #666;
    font-style: italic;
  }
  
  h2 {
    margin: 1.5rem 0 0.5rem;
    text-align: center;
    color: #333;
    font-size: 1.4rem;
  }
  
  .info {
    text-align: center;
    color: #666;
    margin: 0 0 1.5rem;
    font-size: 0.9rem;
  }
  
  /* Step indicator */
  .step-indicator {
    display: flex;
    justify-content: center;
    gap: 2rem;
    margin-bottom: 2rem;
  }
  
  .step {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #f0f0f0;
    color: #999;
    font-weight: 600;
    transition: all 0.3s;
    border: 2px solid transparent;
  }
  
  .step.active {
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: white;
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.4);
  }
  
  .step.completed {
    background: #4caf50;
    color: white;
    border-color: #45a049;
  }
  
  /* Phone input */
  .phone-input-group {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
  }
  
  .country-select {
    flex: 0 0 auto;
    padding: 0.75rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    background: white;
    font-size: 1rem;
    cursor: pointer;
  }
  
  .phone-input {
    flex: 1;
    padding: 0.75rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 1.1rem;
    transition: all 0.3s;
  }
  
  .phone-input:focus {
    outline: none;
    border-color: var(--primary-gold);
    box-shadow: 0 0 10px rgba(255, 215, 0, 0.2);
  }
  
  /* Code input */
  .code-input-wrapper {
    display: flex;
    justify-content: center;
    margin-bottom: 1rem;
  }
  
  .code-input {
    width: 200px;
    padding: 1rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 1.5rem;
    text-align: center;
    letter-spacing: 0.5rem;
    font-weight: 600;
    transition: all 0.3s;
  }
  
  .code-input:focus {
    outline: none;
    border-color: var(--primary-gold);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  /* General input */
  .input {
    width: 100%;
    padding: 0.75rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 1rem;
    margin-bottom: 1rem;
    transition: all 0.3s;
  }
  
  .input:focus {
    outline: none;
    border-color: var(--primary-gold);
    box-shadow: 0 0 10px rgba(255, 215, 0, 0.2);
  }
  
  .input:disabled,
  .phone-input:disabled,
  .code-input:disabled,
  .country-select:disabled {
    background: #f5f5f5;
    cursor: not-allowed;
    opacity: 0.7;
  }
  
  /* Error message */
  .error {
    color: #e74c3c;
    text-align: center;
    margin: 0.75rem 0;
    font-size: 0.9rem;
    font-weight: 500;
  }
  
  /* Submit button */
  .submit-btn {
    width: 100%;
    padding: 1rem;
    background: linear-gradient(135deg, var(--primary-gold), #ffb300);
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
    margin-top: 0.5rem;
  }
  
  .submit-btn:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 5px 20px rgba(255, 215, 0, 0.4);
  }
  
  .submit-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  
  /* Back button */
  .back-btn {
    width: 100%;
    padding: 0.75rem;
    background: transparent;
    color: #666;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    font-size: 0.9rem;
    cursor: pointer;
    margin-top: 1rem;
    transition: all 0.3s;
  }
  
  .back-btn:hover:not(:disabled) {
    background: #f9f9f9;
  }
  
  /* Link button */
  .link-btn {
    background: none;
    border: none;
    color: var(--primary-gold);
    cursor: pointer;
    font-weight: 600;
    text-decoration: underline;
    font-size: 0.9rem;
  }
  
  .link-btn:disabled {
    cursor: not-allowed;
    opacity: 0.6;
  }
  
  /* Resend section */
  .resend-section {
    text-align: center;
    margin-top: 1rem;
  }
  
  .resend-timer {
    color: #999;
    font-size: 0.9rem;
  }
  
  /* Privacy note */
  .privacy-note {
    margin-top: 1.5rem;
    padding: 0.75rem;
    background: rgba(255, 215, 0, 0.1);
    border-left: 3px solid var(--primary-gold);
    border-radius: 4px;
    font-size: 0.85rem;
    color: #666;
  }
  
  /* Welcome verse */
  .verse-welcome {
    margin-top: 2rem;
    padding: 1rem;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.05), rgba(30, 144, 255, 0.05));
    border-radius: 8px;
    text-align: center;
    font-style: italic;
    color: #555;
    line-height: 1.5;
  }
  
  .verse-ref {
    display: block;
    margin-top: 0.5rem;
    font-size: 0.85rem;
    color: #888;
  }
  
  /* Mobile adjustments */
  @media (max-width: 480px) {
    .login-card {
      padding: 1.5rem;
    }
    
    h1 {
      font-size: 1.8rem;
    }
    
    .step-indicator {
      gap: 1.5rem;
    }
    
    .step {
      width: 35px;
      height: 35px;
    }
  }
</style>