(module cjson *

(import chicken scheme foreign)
(use srfi-1)

(foreign-declare "#include \"cJSON/cJSON.c\"")

(define-record-type cjson (%make-cjson pointer)
  %cjson?
  (pointer %cjson-pointer))

(define-foreign-type cjson (c-pointer (struct "cJSON"))
  %cjson-pointer
  (lambda (x) (and x (%make-cjson x))))

;; memory-leaking version. must call free on returned object sometime.
(define string->cjson*
  (foreign-lambda* cjson ((nonnull-c-string json_str))
                   "return(cJSON_Parse(json_str));"))

(define (cjson-assert cjson)
  (if (%cjson-pointer cjson) cjson))

(define cjson-free (foreign-lambda* void ((cjson x)) "cJSON_Delete(x);"))

;; finelizers don't always work out too well if there are many of them
;; (according to docs). how many are too many?
(define (string->cjson str)
  (set-finalizer! (let ((cjson (string->cjson* str)))
                    (if cjson cjson
                        (error "unparseable json" str)))
                  cjson-free))

(define (cjson->string cjson #!optional (pp #t))
  ((if pp
       (foreign-lambda* c-string* ((cjson json)) "return (cJSON_Print(json));")
       (foreign-lambda* c-string* ((cjson json)) "return (cJSON_PrintUnformatted(json));"))
   cjson))


(define cjson/false  0)
(define cjson/true   1)
(define cjson/null   2)
(define cjson/number 3)
(define cjson/string 4)
(define cjson/array  5)
(define cjson/object 6)

;; no error checking!
(define cjson-type   (foreign-lambda* int      ((cjson x)) "return(x->type);"))
(define cjson-int    (foreign-lambda* int      ((cjson x)) "return(x->valueint);"))
(define cjson-double (foreign-lambda* double   ((cjson x)) "return(x->valuedouble);"))
(define cjson-string (foreign-lambda* c-string ((cjson x)) "return(x->valuestring);"))
(define cjson-key    (foreign-lambda* c-string ((cjson x)) "return(x->string);"))

(define cjson-array-size (foreign-lambda int cJSON_GetArraySize cjson))
(define cjson-array-ref  (foreign-lambda cjson cJSON_GetArrayItem cjson int))
(define cjson-obj-ref    (foreign-lambda cjson cJSON_GetObjectItem cjson nonnull-c-string))

(define cjson-child   (foreign-lambda* cjson ((cjson x)) "return(x->child);" ))
(define cjson-next    (foreign-lambda* cjson ((cjson x)) "return(x->next);" ))

;;cJSON *c=object->child; while (c && cJSON_strcasecmp(c->string,string)) c=c->next; return c;
(define (cjson-obj-keys cjson)
  (let loop ((c (cjson-child cjson))
             (res '()))
    (if (and c (%cjson-pointer c))
        (loop (cjson-next c) (cons (cjson-key c) res))
        res)))

;; number => number, string => string
;; nil => (void), true/false => #t/#f
;; array => vector
;; obj => alist
(define (cjson-schemify cjson)
  (select
   (cjson-type cjson)
   ((cjson/false) #f)
   ((cjson/true)  #t)
   ((cjson/null) (void))                        ;; null
   ((cjson/number) (cjson-double cjson))        ;; cjson-number
   ((cjson/string) (cjson-string cjson))
   ((cjson/array)
    (list->vector
     (map cjson-schemify (list-tabulate (cjson-array-size cjson)
                                        (lambda (i) (cjson-array-ref cjson i))))))
   ((cjson/object)
    (map (lambda (key)
           (cons (string->symbol key)
                 (cjson-schemify (cjson-obj-ref cjson key))))
         (cjson-obj-keys cjson)))
   (else (error "unknown cjson type" (cjson-type cjson)))))

;; finalizers are expensive. this version avoids their use:
(define (string->json str)
  (let* ((j (string->cjson* str))
         (s (cjson-schemify j)))
    (cjson-free j)
    s))

(define-record-printer (cjson x out)
  (display "#<cjson " out)
  (display (cjson->string x #f) out)
  (display ">" out))

)
