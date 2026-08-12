// js admin color picker
jQuery(document).ready(function($){
    if ($.fn.wpColorPicker) {
        $('.my-color-field, .clbntb_color').wpColorPicker();
    }
    
     function validatePhoneNumber(input) {
      var phoneNumberPattern = /^\d{8,12}$/; // Regular expression to match a phone number with 8 to 12 digits
      if (input.value.trim() !== '' && !phoneNumberPattern.test(input.value.trim())) {
        input.classList.add('invalid');
        return false;
      } else {
        input.classList.remove('invalid');
        return true;
      }
    }

    var phoneInputs = document.querySelectorAll('input[name="clbntb_phone"], input[name="clbntb_phone2"], input[name="clbntb_phone3"]');
    phoneInputs.forEach(function(input) {
      input.addEventListener('change', function() {
        validatePhoneNumber(this);
      });
    });

    var formContact = document.getElementById('form-button-contact');
    if (formContact) {
      formContact.addEventListener('submit', function(event) {
        var allValid = true;
        phoneInputs.forEach(function(input) {
          if (!validatePhoneNumber(input)) {
            allValid = false;
          }
        });
        if (!allValid) {
          event.preventDefault(); // Ngăn không cho gửi form nếu có bất kỳ trường nào không hợp lệ
          alert('Vui lòng sửa các số điện thoại không hợp lệ.');
        }
      });
    }
    
    
    
    function validateURL(input) {
      var urlPattern = /^(ftp|http|https):\/\/[^ "]+$/; // Regular expression to match a URL
      if (input.value.trim() !== '' && !urlPattern.test(input.value.trim())) {
        input.classList.add('invalid');
        return false;
      } else {
        input.classList.remove('invalid');
        return true;
      }
    }
    var urlInputs = document.querySelectorAll('input[name="clbntb_telegram"], input[name="clbntb_instagram"], input[name="clbntb_youtube"], input[name="clbntb_tiktok"], input[name="clbntb_linkfanpage"]');
    urlInputs.forEach(function(input) {
      input.addEventListener('change', function() {
        validateURL(this);
      });
    });
    if (formContact) {
      formContact.addEventListener('submit', function(event) {
        var allValid = true;
        urlInputs.forEach(function(input) {
          if (!validateURL(input)) {
            allValid = false;
          }
        });
        if (!allValid) {
          event.preventDefault(); // Ngăn không cho gửi form nếu có bất kỳ trường nào không hợp lệ
          alert('Vui lòng sửa các đường dẫn (URL) không hợp lệ.');
        }
      });
    }
});