<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  
  const dispatch = createEventDispatcher();
  
  let isRecording = false;
  let isTranscribing = false;
  let mediaRecorder: MediaRecorder | null = null;
  let audioChunks: Blob[] = [];
  let recordingTime = 0;
  let recordingInterval: NodeJS.Timeout | null = null;
  
  export let placeholder = "Tap microphone to speak...";
  export let maxDuration = 60; // Maximum recording duration in seconds
  
  function formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }
  
  async function startRecording() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      mediaRecorder = new MediaRecorder(stream, {
        mimeType: 'audio/webm'
      });
      
      audioChunks = [];
      
      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          audioChunks.push(event.data);
        }
      };
      
      mediaRecorder.onstop = async () => {
        const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
        await transcribeAudio(audioBlob);
        
        // Stop all tracks to release microphone
        stream.getTracks().forEach(track => track.stop());
      };
      
      mediaRecorder.start();
      isRecording = true;
      recordingTime = 0;
      
      // Start recording timer
      recordingInterval = setInterval(() => {
        recordingTime++;
        if (recordingTime >= maxDuration) {
          stopRecording();
        }
      }, 1000);
      
    } catch (error) {
      console.error('Error accessing microphone:', error);
      dispatch('error', { 
        message: 'Could not access microphone. Please check permissions.' 
      });
    }
  }
  
  function stopRecording() {
    if (mediaRecorder && isRecording) {
      mediaRecorder.stop();
      isRecording = false;
      
      if (recordingInterval) {
        clearInterval(recordingInterval);
        recordingInterval = null;
      }
    }
  }
  
  async function transcribeAudio(audioBlob: Blob) {
    isTranscribing = true;
    
    try {
      // Convert blob to base64
      const reader = new FileReader();
      reader.readAsDataURL(audioBlob);
      
      const base64Audio = await new Promise<string>((resolve) => {
        reader.onloadend = () => {
          const base64 = reader.result as string;
          resolve(base64.split(',')[1]); // Remove data:audio/webm;base64, prefix
        };
      });
      
      // Call our transcription API
      const response = await fetch('/api/transcribe', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          audio: base64Audio
        })
      });
      
      const data = await response.json();
      
      if (data.success && data.text) {
        dispatch('transcription', { text: data.text });
      } else {
        throw new Error(data.error || 'Transcription failed');
      }
      
    } catch (error) {
      console.error('Transcription error:', error);
      dispatch('error', { 
        message: 'Failed to transcribe audio. Please try again.' 
      });
    } finally {
      isTranscribing = false;
    }
  }
  
  function toggleRecording() {
    if (isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  }
</script>

<div class="voice-recorder">
  <button 
    class="mic-button"
    class:recording={isRecording}
    class:transcribing={isTranscribing}
    on:click={toggleRecording}
    disabled={isTranscribing}
    title={isRecording ? 'Stop recording' : 'Start voice recording'}
  >
    {#if isTranscribing}
      <span class="spinner">⟳</span>
    {:else if isRecording}
      <span class="mic-icon recording">🎤</span>
      <span class="recording-time">{formatTime(recordingTime)}</span>
    {:else}
      <span class="mic-icon">🎙️</span>
    {/if}
  </button>
  
  {#if !isRecording && !isTranscribing}
    <span class="hint">{placeholder}</span>
  {/if}
  
  {#if isRecording}
    <div class="recording-indicator">
      <span class="pulse"></span>
      Recording... Tap to stop
    </div>
  {/if}
  
  {#if isTranscribing}
    <div class="transcribing-indicator">
      Transcribing your words...
    </div>
  {/if}
</div>

<style>
  .voice-recorder {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
    margin: 0.5rem 0;
  }
  
  .mic-button {
    width: 60px;
    height: 60px;
    border-radius: 50%;
    background: linear-gradient(135deg, rgba(138, 43, 226, 0.1), rgba(255, 215, 0, 0.1));
    border: 2px solid var(--border-gold, #ffd700);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: all 0.3s;
    position: relative;
  }
  
  .mic-button:hover:not(:disabled) {
    transform: scale(1.05);
    box-shadow: 0 0 20px rgba(255, 215, 0, 0.3);
  }
  
  .mic-button.recording {
    background: linear-gradient(135deg, rgba(255, 87, 34, 0.2), rgba(255, 215, 0, 0.2));
    border-color: #ff5722;
    animation: pulse-border 1.5s infinite;
  }
  
  .mic-button.transcribing {
    background: linear-gradient(135deg, rgba(33, 150, 243, 0.2), rgba(255, 215, 0, 0.2));
    border-color: #2196f3;
    cursor: not-allowed;
  }
  
  .mic-button:disabled {
    opacity: 0.7;
  }
  
  @keyframes pulse-border {
    0% {
      box-shadow: 0 0 0 0 rgba(255, 87, 34, 0.7);
    }
    70% {
      box-shadow: 0 0 0 10px rgba(255, 87, 34, 0);
    }
    100% {
      box-shadow: 0 0 0 0 rgba(255, 87, 34, 0);
    }
  }
  
  .mic-icon {
    font-size: 1.5rem;
  }
  
  .mic-icon.recording {
    color: #ff5722;
  }
  
  .recording-time {
    font-size: 0.7rem;
    color: #ff5722;
    font-weight: bold;
  }
  
  .spinner {
    font-size: 1.5rem;
    animation: spin 1s linear infinite;
  }
  
  @keyframes spin {
    from {
      transform: rotate(0deg);
    }
    to {
      transform: rotate(360deg);
    }
  }
  
  .hint {
    font-size: 0.85rem;
    color: var(--text-scripture, #999);
    font-style: italic;
  }
  
  .recording-indicator {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: #ff5722;
    font-size: 0.9rem;
    font-weight: 600;
  }
  
  .pulse {
    width: 8px;
    height: 8px;
    background: #ff5722;
    border-radius: 50%;
    animation: pulse 1s infinite;
  }
  
  @keyframes pulse {
    0%, 100% {
      opacity: 1;
      transform: scale(1);
    }
    50% {
      opacity: 0.5;
      transform: scale(1.2);
    }
  }
  
  .transcribing-indicator {
    color: #2196f3;
    font-size: 0.9rem;
    font-style: italic;
  }
</style>