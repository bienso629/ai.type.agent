jQuery(function($){
    function optimizeOne(id, nonce, $el){
        if($el && $el.data('busy')) return;
        if($el){ $el.data('busy', true).addClass('mob-busy').text(MOB.i18n.optimizing); }
        $.post(MOB.ajaxUrl, { action: 'mob_optimize_image', id: id, _wpnonce: nonce })
            .done(function(resp){
                if(resp && resp.success){
                    if($el){ $el.text(MOB.i18n.done).removeClass('mob-busy'); }
                }else{
                    var msg = (resp && resp.data) ? resp.data : MOB.i18n.failed;
                    if($el){ $el.text('Optimize').removeClass('mob-busy'); }
                    window.alert('MOB: ' + msg);
                }
            })
            .fail(function(){
                if($el){ $el.text('Optimize').removeClass('mob-busy'); }
                window.alert('MOB: AJAX failed (có thể do PHP fatal). Hãy bật WP_DEBUG_LOG để xem lỗi chi tiết.');
            });
    }

    $(document).on('click', '.mob-optimize-link', function(e){
        e.preventDefault();
        var $a = $(this);
        optimizeOne($a.data('id'), $a.data('nonce'), $a);
    });

    $(document).on('click', '.mob-optimize-btn', function(e){
        e.preventDefault();
        var $btn = $(this);
        optimizeOne($btn.data('id'), $btn.data('nonce'), $btn);
    });
});
