document.addEventListener("DOMContentLoaded", function () {
  // Don't show on playground
  if (window.location.pathname.startsWith("/playground")) return;

  const main = document.querySelector(".md-content__inner");
  if (!main) return;

  let feedbackVisible = false; // to ensure it only shows once

  function showFeedbackPopup() {
    if (feedbackVisible) return; // Don't create twice
    feedbackVisible = true;

    // Create feedback popup
    const feedback = document.createElement("div");
    feedback.className = "feedback-popup";
    feedback.innerHTML = `
      <div class="feedback-container">
        <button id="feedback-close" class="feedback-close" title="Close">×</button>
        <div class="feedback-title">How do you like the documentation?</div>
        <div class="feedback-buttons">
          <button class="thumb" data-type="up" title="Thumbs up">👍</button>
          <button class="thumb" data-type="down" title="Thumbs down">👎</button>
        </div>
        <textarea id="feedback-comment" class="feedback-textarea" rows="2" placeholder="Any comments? (optional)"></textarea>
        <button id="feedback-send" class="feedback-send">Send</button>
        <span id="feedback-status" class="feedback-status"></span>
      </div>
    `;
    document.body.appendChild(feedback);

    const status = feedback.querySelector("#feedback-status");
    const sendBtn = feedback.querySelector("#feedback-send");
    const closeBtn = feedback.querySelector("#feedback-close");
    const thumbs = feedback.querySelectorAll('.thumb');
    let rating = null;

    function updateThumbs() {
      thumbs.forEach(btn => btn.classList.toggle('selected', rating === btn.getAttribute('data-type')));
      sendBtn.disabled = !rating;
      sendBtn.classList.toggle('active', !!rating);
      sendBtn.textContent = rating ? 'Send' : 'Select rating';
    }
    updateThumbs();

    thumbs.forEach(btn => {
      btn.onclick = function () {
        rating = btn.getAttribute('data-type');
        updateThumbs();
      };
    });

    sendBtn.onclick = function () {
      if (!rating) return;
      sendFeedback();
    };

    closeBtn.onclick = function () {
      feedback.remove();
    };

    function sendFeedback() {
      const comment = feedback.querySelector("#feedback-comment").value;
      const page = document.title || window.location.pathname;
      status.textContent = "Sending...";
      sendBtn.disabled = true;
      fetch("https://script.google.com/macros/s/AKfycbwnF5MK6hrie4f4V0beTtRYueGrjBIBfBvlsiGnMEeeoMhJpJS8H5hDU8BzU5c9AhJ3/exec", {
        method: "POST",
        body: JSON.stringify({ page, rating, comment }),
        headers: { "Content-Type": "application/json" }
      })
        .then(() => {
          status.textContent = "Thank you for your feedback!";
          sendBtn.disabled = true;
          setTimeout(() => { feedback.remove(); }, 2500);
        })
        .catch(() => {
          status.textContent = "Error sending feedback.";
          sendBtn.disabled = false;
        });
    }
  }

  // Detect when user scrolls to 95% of the     page
  window.addEventListener('scroll', function () {
  const scrollTop = window.scrollY;
  const windowHeight = window.innerHeight;
  const docHeight = document.documentElement.scrollHeight;
  const scrolledPercent = (scrollTop + windowHeight) / docHeight * 100;

  if (scrolledPercent >= 95) {
    showFeedbackPopup();
  }
});
});
